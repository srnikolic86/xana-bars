-- XanaBars
-- Shows the normal action bars (slots 1-72 + right bars) while WoW Forever's
-- Gamepad UI is enabled. The bars are the addon's own secure buttons built on
-- Blizzard's ActionBarButtonTemplate, so they do not touch or re-show the
-- Blizzard bars that the Gamepad UI hides, and cannot conflict with them.

local ADDON = ...
local NUM_BUTTONS = 12

local BAR_DEFS = {
	{ label = "Main bar",         paged = true, binding = "ACTIONBUTTON%d",         cols = 12, enabled = true,  point = { "BOTTOM", "BOTTOM", 0, 200 } },
	{ label = "Bottom left bar",  page = 6,     binding = "MULTIACTIONBAR1BUTTON%d", cols = 12, enabled = true,  point = { "BOTTOM", "BOTTOM", 0, 250 } },
	{ label = "Bottom right bar", page = 5,     binding = "MULTIACTIONBAR2BUTTON%d", cols = 12, enabled = true,  point = { "BOTTOM", "BOTTOM", 0, 300 } },
	{ label = "Right bar",        page = 3,     binding = "MULTIACTIONBAR3BUTTON%d", cols = 1,  enabled = false, point = { "RIGHT", "RIGHT", -10, 0 } },
	{ label = "Right bar 2",      page = 4,     binding = "MULTIACTIONBAR4BUTTON%d", cols = 1,  enabled = false, point = { "RIGHT", "RIGHT", -60, 0 } },
}

local db
local header
local bars = {}
local allButtons = {}
local gridShown = false

local HasActionFn = HasAction or (C_ActionBar and C_ActionBar.HasAction)

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33bbffXanaBars:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Combat lockdown helper: protected changes wait until combat ends
---------------------------------------------------------------------------
local pending = {}
local function AfterCombat(key, fn)
	if InCombatLockdown() then
		pending[key] = fn
	else
		fn()
	end
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local function InitDB()
	XanaBarsDB = XanaBarsDB or {}
	db = XanaBarsDB
	if db.mode == nil then db.mode = "auto" end          -- "auto" = only with Gamepad UI, "always"
	if db.scale == nil then db.scale = 1 end
	if db.alpha == nil then db.alpha = 1 end
	if db.showEmpty == nil then db.showEmpty = true end
	if db.hotkeys == nil then db.hotkeys = true end
	if db.spacing == nil then db.spacing = 4 end
	db.bars = db.bars or {}
	for i, def in ipairs(BAR_DEFS) do
		local b = db.bars[i] or {}
		db.bars[i] = b
		if b.enabled == nil then b.enabled = def.enabled end
		if b.cols == nil then b.cols = def.cols end
		if b.point == nil then b.point = { unpack(def.point) } end
	end
end

---------------------------------------------------------------------------
-- Settings macro. The Forever beta writes SavedVariables at logout but never
-- loads them back, so the settings are also kept in a character-specific macro
-- whose body is a no-op "/xbdata ..." line, and read from there at login:
--   /xbdata 1|<a=auto, w=always>|scale|alpha|empty|hotkeys|<bar>;<bar>;...
--   <bar> = enabled,cols,anchor,x,y
---------------------------------------------------------------------------
local MACRO_NAME = "XanaBars"
local DATA_TAG = "/xbdata "
local ANCHOR_CODES = {
	TOPLEFT = "TL", TOP = "T", TOPRIGHT = "TR", LEFT = "L", CENTER = "C",
	RIGHT = "R", BOTTOMLEFT = "BL", BOTTOM = "B", BOTTOMRIGHT = "BR",
}
local CODE_ANCHORS = {}
for anchor, code in pairs(ANCHOR_CODES) do CODE_ANCHORS[code] = anchor end

local macrosReady, saveWanted, warnedMacro

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function Round(v) return math.floor(v + 0.5) end

-- Only character-specific macros count. General (account) macros fill indexes
-- 1..numAccount with no gaps and character macros come after them; the scan end
-- just needs to be beyond the last possible macro index on any client.
local MACRO_SCAN_END = 300

local function FindSettingsMacro()
	for i = (GetNumMacros() or 0) + 1, MACRO_SCAN_END do
		local name, _, body = GetMacroInfo(i)
		if name and body and body:find(DATA_TAG, 1, true) then return i end
	end
end

-- The settings as one line (without the macro's "/xbdata " tag).
local function SettingsData()
	local parts = {}
	for i, b in ipairs(db.bars) do
		parts[i] = ("%d,%d,%s,%d,%d"):format(b.enabled and 1 or 0, b.cols,
			ANCHOR_CODES[b.point[1]] or "C", Round(b.point[3]), Round(b.point[4]))
	end
	return ("1|%s|%g|%g|%d|%d|%s"):format(db.mode == "always" and "w" or "a",
		db.scale, db.alpha, db.showEmpty and 1 or 0, db.hotkeys and 1 or 0, table.concat(parts, ";"))
end

-- Copies a SettingsData() line into db. Returns false if it isn't one.
local function ApplySettingsData(data)
	local version, mode, scale, alpha, empty, hotkeys, barData = strsplit("|", data)
	if version ~= "1" then return false end
	db.mode = (mode == "w") and "always" or "auto"
	db.scale = Clamp(tonumber(scale) or 1, 0.5, 2)
	db.alpha = Clamp(tonumber(alpha) or 1, 0.1, 1)
	db.showEmpty = (empty ~= "0")
	db.hotkeys = (hotkeys ~= "0")
	for i, entry in ipairs({ strsplit(";", barData or "") }) do
		local b = db.bars[i]
		local enabled, cols, code, x, y = strsplit(",", entry)
		local anchor = code and CODE_ANCHORS[code]
		if b and tonumber(cols) and anchor and tonumber(x) and tonumber(y) then
			b.enabled = (enabled == "1")
			b.cols = Clamp(math.floor(tonumber(cols)), 1, NUM_BUTTONS)
			b.point = { anchor, anchor, tonumber(x), tonumber(y) }
		end
	end
	return true
end

-- Copies the settings macro into db. Returns true if one was found.
local function LoadSettingsMacro()
	local index = FindSettingsMacro()
	if not index then return false end
	local _, _, body = GetMacroInfo(index)
	return ApplySettingsData(body:match("/xbdata ([^\n]*)") or "")
end

-- Macros can't be edited in combat, and must not be written before the
-- existing ones have loaded (or a second settings macro would be created).
local function SaveSettings()
	if InCombatLockdown() then AfterCombat("save", SaveSettings) return end
	if not macrosReady then saveWanted = true return end
	local body = DATA_TAG .. SettingsData()
	local index = FindSettingsMacro()
	if index then
		local _, _, old = GetMacroInfo(index)
		if old ~= body then EditMacro(index, nil, nil, body) end
		return
	end
	local ok, created = pcall(CreateMacro, MACRO_NAME, 134400, body, true)
	if (not ok or not created or created == 0) and not warnedMacro then
		warnedMacro = true
		Print("Couldn't create the XanaBars settings macro (are this character's macro slots full?). " ..
			"Settings won't survive a logout until one is free.")
	end
end

---------------------------------------------------------------------------
-- Gamepad UI detection (Blizzard's own check in the Forever UI source)
---------------------------------------------------------------------------
local function GamepadUIActive()
	if InputUtil and InputUtil.IsGamepadUIEnabled then
		local ok, value = pcall(InputUtil.IsGamepadUIEnabled)
		if ok then
			return value and true or false, true
		end
	end
	return false, false -- state unknown
end

local function ShouldShow()
	if db.mode == "always" then return true end
	local active, known = GamepadUIActive()
	if not known then return true end
	return active
end

---------------------------------------------------------------------------
-- Button visuals: hotkey text and empty-slot fading
---------------------------------------------------------------------------
local function UpdateHotkey(btn)
	local hk = btn.HotKey or (btn:GetName() and _G[btn:GetName() .. "HotKey"])
	if not hk then return end
	local key = db.hotkeys and btn.padBinding and GetBindingKey(btn.padBinding)
	if key then
		hk:SetText(GetBindingText(key, 1))
		hk:Show()
	else
		hk:SetText("")
	end
end

local function UpdateEmpty(btn)
	local slot
	if btn:GetID() > 0 then
		slot = btn:GetID() + ((tonumber(btn:GetAttribute("actionpage")) or 1) - 1) * NUM_BUTTONS
	else
		slot = btn:GetAttribute("action")
	end
	local has = slot and HasActionFn and HasActionFn(slot)
	if has or db.showEmpty or gridShown then
		btn:SetAlpha(1)
	else
		btn:SetAlpha(0)
	end
end

local function RefreshButtons()
	for _, btn in ipairs(allButtons) do
		UpdateEmpty(btn)
		UpdateHotkey(btn)
	end
end

---------------------------------------------------------------------------
-- Layout / visibility (protected, so always routed through AfterCombat)
---------------------------------------------------------------------------
local function LayoutBar(index)
	local bar, bdb = bars[index], db.bars[index]
	local size = bar.buttons[1]:GetWidth()
	if not size or size < 10 then size = 36 end
	local cols = math.max(1, math.min(NUM_BUTTONS, bdb.cols or 12))
	local rows = math.ceil(NUM_BUTTONS / cols)
	local step = size + db.spacing

	for i, btn in ipairs(bar.buttons) do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", bar, "TOPLEFT", col * step, -row * step)
	end
	bar:SetSize(cols * step - db.spacing, rows * step - db.spacing)
	bar:SetScale(db.scale)
	bar:SetAlpha(db.alpha)
	bar:ClearAllPoints()
	local p = bdb.point
	bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	bar:SetShown(bdb.enabled)
end

local unlocked = false

-- A bar's blue mover box is visible only while unlocked AND the bar itself is visible.
local function UpdateMovers()
	for i, bar in ipairs(bars) do
		if bar.mover then
			bar.mover:SetShown(unlocked and db.bars[i].enabled and header:IsShown())
		end
	end
end

local function ApplyAll()
	AfterCombat("apply", function()
		for i in ipairs(bars) do LayoutBar(i) end
		header:SetShown(ShouldShow())
		RefreshButtons()
		UpdateMovers()
	end)
end

---------------------------------------------------------------------------
-- Movers (shown while unlocked)
---------------------------------------------------------------------------
local StartDrag, StopDrag
---------------------------------------------------------------------------
-- Dragging with snapping. The bar follows the cursor by hand (instead of
-- StartMoving) so its position can be corrected every frame. All numbers are
-- in the bars' own scaled units; every bar shares db.scale, so they compare 1:1.
---------------------------------------------------------------------------
local SNAP_RANGE = 12
local dragIndex, dragOffX, dragOffY
local dragDriver = CreateFrame("Frame")
dragDriver:Hide()

local function CursorInBarUnits(bar)
	local x, y = GetCursorPosition()
	local es = bar:GetEffectiveScale()
	return x / es, y / es
end

-- Returns the best snapped value for one axis, or the original when nothing is close.
local function BestSnap(value, candidates)
	local best, bestDist = value, SNAP_RANGE
	for _, c in ipairs(candidates) do
		local d = math.abs(c - value)
		if d < bestDist then best, bestDist = c, d end
	end
	return best
end

local function SnapPosition(index, L, B, W, H)
	if IsShiftKeyDown() then return L, B end -- hold Shift to place freely
	local gap = db.spacing
	local reach = SNAP_RANGE + gap
	local scale = bars[index]:GetScale()
	local screenW, screenH = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
	local xs = { screenW / 2 - W / 2 } -- screen centre
	local ys = {}

	for i, other in ipairs(bars) do
		if i ~= index and db.bars[i].enabled and other:IsShown() and other:GetLeft() then
			local oL, oB = other:GetLeft(), other:GetBottom()
			local oW, oH = other:GetWidth(), other:GetHeight()
			local oR, oT = oL + oW, oB + oH
			-- only snap to bars that are actually nearby
			if L < oR + reach and L + W > oL - reach and B < oT + reach and B + H > oB - reach then
				xs[#xs + 1] = oL                     -- left edges aligned
				xs[#xs + 1] = oR - W                 -- right edges aligned
				xs[#xs + 1] = oL + oW / 2 - W / 2    -- centred
				xs[#xs + 1] = oR + gap               -- sitting to the right
				xs[#xs + 1] = oL - gap - W           -- sitting to the left
				ys[#ys + 1] = oB                     -- bottom edges aligned
				ys[#ys + 1] = oT - H                 -- top edges aligned
				ys[#ys + 1] = oB + oH / 2 - H / 2    -- centred
				ys[#ys + 1] = oT + gap               -- stacked on top
				ys[#ys + 1] = oB - gap - H           -- stacked underneath
			end
		end
	end
	L, B = BestSnap(L, xs), BestSnap(B, ys)
	-- keep the bar on screen
	L = math.max(0, math.min(screenW - W, L))
	B = math.max(0, math.min(screenH - H, B))
	return L, B
end

function StopDrag()
	if not dragIndex then return end
	local index, bar = dragIndex, bars[dragIndex]
	dragIndex = nil
	dragDriver:Hide()
	if not bar:GetLeft() then return end

	-- Save relative to the nearest screen anchor so the bar stays put sensibly
	-- when the resolution, scale or number of columns changes later.
	local scale = bar:GetScale()
	local screenW, screenH = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
	local L, B, W, H = bar:GetLeft(), bar:GetBottom(), bar:GetWidth(), bar:GetHeight()
	local cx, cy = L + W / 2, B + H / 2
	local hp, x = "", cx - screenW / 2
	if cx < screenW / 3 then hp, x = "LEFT", L elseif cx > screenW * 2 / 3 then hp, x = "RIGHT", L + W - screenW end
	local vp, y = "", cy - screenH / 2
	if cy < screenH / 3 then vp, y = "BOTTOM", B elseif cy > screenH * 2 / 3 then vp, y = "TOP", B + H - screenH end
	local point = vp .. hp
	if point == "" then point = "CENTER" end
	db.bars[index].point = { point, point, x, y }
	SaveSettings()

	if not InCombatLockdown() then
		bar:ClearAllPoints()
		bar:SetPoint(point, UIParent, point, x, y)
	end
end

function StartDrag(index)
	if InCombatLockdown() then return end
	local bar = bars[index]
	if not bar:GetLeft() then return end
	local cx, cy = CursorInBarUnits(bar)
	dragIndex, dragOffX, dragOffY = index, cx - bar:GetLeft(), cy - bar:GetBottom()
	dragDriver:Show()
end

dragDriver:SetScript("OnUpdate", function()
	if not dragIndex then dragDriver:Hide() return end
	if InCombatLockdown() then StopDrag() return end
	local bar = bars[dragIndex]
	local cx, cy = CursorInBarUnits(bar)
	local L, B = SnapPosition(dragIndex, cx - dragOffX, cy - dragOffY, bar:GetWidth(), bar:GetHeight())
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", L, B)
end)

local function CreateMover(index)
	local bar = bars[index]
	local mover = CreateFrame("Frame", nil, UIParent)
	mover:SetFrameStrata("DIALOG")
	mover:SetAllPoints(bar)
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:Hide()

	local tex = mover:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints()
	tex:SetColorTexture(0, 0.6, 1, 0.4)

	local text = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER")
	text:SetText(index .. ": " .. BAR_DEFS[index].label)

	mover:SetScript("OnDragStart", function() StartDrag(index) end)
	mover:SetScript("OnDragStop", StopDrag)
	mover:SetScript("OnHide", function() if dragIndex == index then StopDrag() end end)
	bar.mover = mover
end

local function SetLocked(locked)
	if not locked and InCombatLockdown() then
		Print("Can't unlock in combat.")
		return
	end
	unlocked = not locked
	UpdateMovers()
	Print(locked and "Bars locked." or "Bars unlocked - drag the blue boxes (they snap to each other, hold Shift to place freely), then /xbars lock.")
end

---------------------------------------------------------------------------
-- Bar creation
---------------------------------------------------------------------------
local pagingConditions
local function PagingConditions()
	if pagingConditions then return pagingConditions end
	local function index(fn, fallback)
		local f = _G[fn]
		if type(f) == "function" then
			local ok, v = pcall(f)
			if ok and type(v) == "number" and v > 0 then return v end
		end
		return fallback
	end
	local vehicle = index("GetVehicleBarIndex", 12)
	local override = index("GetOverrideBarIndex", 14)
	local tempShapeshift = index("GetTempShapeshiftBarIndex", 13)
	pagingConditions = ("[vehicleui]%d;[overridebar]%d;[possessbar]%d;[shapeshift]%d;"):format(
			vehicle, override, vehicle, tempShapeshift) ..
		"[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6;" ..
		"[bonusbar:1]7;[bonusbar:2]8;[bonusbar:3]9;[bonusbar:4]10;[bonusbar:5]11;1"
	return pagingConditions
end

local function CreateButton(bar, barIndex, i)
	local name = "XanaBarsBar" .. barIndex .. "Button" .. i
	local ok, btn = pcall(CreateFrame, "CheckButton", name, bar, "ActionBarButtonTemplate")
	if not ok or not btn then return nil end

	btn:SetAttribute("type", "action")
	btn:SetAttribute("showgrid", 1)
	btn:SetAttribute("checkselfcast", true)
	btn:SetAttribute("checkfocuscast", true)
	btn:SetAttribute("checkmouseovercast", true)

	local def = BAR_DEFS[barIndex]
	if def.paged then
		-- This client build cannot run secure snippets (restricted execution is
		-- unavailable), so paging uses a plain attribute driver instead: with a
		-- button ID > 0 the Blizzard template computes slot = ID + (actionpage-1)*12.
		btn:SetID(i)
		btn:SetAttribute("actionpage", 1)
		RegisterAttributeDriver(btn, "actionpage", PagingConditions())
	else
		-- ID 0 makes the template read the slot from the "action" attribute
		btn:SetID(0)
		btn:SetAttribute("action", (def.page - 1) * NUM_BUTTONS + i)
	end

	-- Modern clients decide between key-down / key-up inside the secure click
	-- handler and need both registered; older handlers only want the up click.
	if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("ActionButtonUseKeyDown") ~= nil then
		btn:RegisterForClicks("AnyDown", "AnyUp")
	else
		btn:RegisterForClicks("AnyUp")
	end

	btn.padBinding = def.binding:format(i)
	-- Quick Keybind Mode reads the binding command from button.commandName. Without it
	-- the mode tries to bind a nil action and errors in Blizzard's BindingUtil. Pointing
	-- it at the matching default-bar command lets Quick Keybind work on these buttons.
	btn.commandName = btn.padBinding
	if btn.UpdateHotkeys then
		hooksecurefunc(btn, "UpdateHotkeys", UpdateHotkey)
	end
	btn:Show()
	return btn
end

local function CreateBars()
	header = CreateFrame("Frame", "XanaBarsHeader", UIParent)
	header:SetSize(1, 1)
	header:SetPoint("CENTER")

	for barIndex, def in ipairs(BAR_DEFS) do
		local bar = CreateFrame("Frame", "XanaBarsBar" .. barIndex, header)
		bar:SetMovable(true)
		bar:SetClampedToScreen(true)
		bar.buttons = {}
		for i = 1, NUM_BUTTONS do
			local btn = CreateButton(bar, barIndex, i)
			if not btn then
				Print("Could not create action buttons (ActionBarButtonTemplate missing?). Addon disabled.")
				return false
			end
			bar.buttons[i] = btn
			allButtons[#allButtons + 1] = btn
		end
		bars[barIndex] = bar
		CreateMover(barIndex)
	end

	return true
end

---------------------------------------------------------------------------
-- Export / import strings: "XB1:" + base64 of SettingsData().
-- Base64 keeps "|" out of the edit box, where WoW would read it as an escape code.
---------------------------------------------------------------------------
local EXPORT_PREFIX = "XB1:"
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function Base64Encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local d1, d2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
		local d3, d4 = math.floor(n / 64) % 64, n % 64
		out[#out + 1] = B64:sub(d1 + 1, d1 + 1) .. B64:sub(d2 + 1, d2 + 1)
			.. (b and B64:sub(d3 + 1, d3 + 1) or "=") .. (c and B64:sub(d4 + 1, d4 + 1) or "=")
	end
	return table.concat(out)
end

-- Returns nil for anything that isn't valid base64.
local function Base64Decode(s)
	s = s:gsub("%s", "")
	if #s % 4 ~= 0 then return nil end
	local out = {}
	for i = 1, #s, 4 do
		local n, pad = 0, 0
		for j = i, i + 3 do
			local ch = s:sub(j, j)
			local v = B64:find(ch, 1, true)
			if ch == "=" and j >= i + 2 then
				pad, n = pad + 1, n * 64
			elseif v and pad == 0 then
				n = n * 64 + v - 1
			else
				return nil
			end
		end
		out[#out + 1] = string.char(math.floor(n / 65536) % 256)
			.. (pad < 2 and string.char(math.floor(n / 256) % 256) or "")
			.. (pad < 1 and string.char(n % 256) or "")
	end
	return table.concat(out)
end

-- Returns true if the string was valid.
local function ImportSettings(text)
	text = strtrim(text or "")
	local data = text:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX and Base64Decode(text:sub(#EXPORT_PREFIX + 1))
	if not data or not ApplySettingsData(data) then
		Print("That isn't a XanaBars export string.")
		return false
	end
	StopDrag()
	ApplyAll()
	SaveSettings()
	Print("Bar settings imported.")
	return true
end

-- Window with one text box: shows an export string to copy, or takes one to import.
-- It never moves keyboard focus by itself: doing that from addon code got the
-- addon blocked (and crashed the Forever beta client), so the player clicks the
-- box instead. For the same reason it is a plain EditBox, not InputBoxTemplate,
-- and not registered in UISpecialFrames.
local dialog = CreateFrame("Frame", "XanaBarsDialog", UIParent)
dialog:SetSize(480, 130)
dialog:SetPoint("CENTER", 0, 150)
dialog:SetFrameStrata("FULLSCREEN_DIALOG")
dialog:EnableMouse(true)
dialog:Hide()
dialog.bg = dialog:CreateTexture(nil, "BACKGROUND")
dialog.bg:SetAllPoints()
dialog.bg:SetColorTexture(0, 0, 0, 0.85)
dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dialog.title:SetPoint("TOP", 0, -12)
dialog.hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dialog.hint:SetPoint("TOP", 0, -36)

dialog.box = CreateFrame("EditBox", nil, dialog)
dialog.box:SetSize(440, 24)
dialog.box:SetPoint("TOP", 0, -56)
dialog.box:SetFontObject(ChatFontNormal)
dialog.box:SetTextInsets(6, 6, 0, 0)
dialog.box:SetAutoFocus(false)
dialog.box:SetMaxLetters(0)
dialog.box.bg = dialog.box:CreateTexture(nil, "BACKGROUND")
dialog.box.bg:SetAllPoints()
dialog.box.bg:SetColorTexture(1, 1, 1, 0.12)
dialog.box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
dialog.box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)

dialog.action = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
dialog.action:SetSize(100, 22)
dialog.action:SetPoint("BOTTOM", -56, 14)
dialog.action:SetText("Import")
dialog.action:SetScript("OnClick", function()
	if ImportSettings(dialog.box:GetText()) then dialog:Hide() end
end)

dialog.close = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
dialog.close:SetSize(100, 22)
dialog.close:SetText(CLOSE or "Close")
dialog.close:SetScript("OnClick", function() dialog:Hide() end)

dialog.box:SetScript("OnEscapePressed", function() dialog:Hide() end)
dialog.box:SetScript("OnEnterPressed", function()
	if dialog.mode == "import" then dialog.action:Click() end
end)
dialog.box:SetScript("OnTextChanged", function(self, userInput)
	-- An export string stays as it is, whatever gets typed into it.
	if userInput and dialog.mode == "export" then
		self:SetText(dialog.exportText)
		self:HighlightText()
	end
end)

-- Opens on the next frame, so the chat box that ran the slash command has
-- finished closing first.
function dialog:Open(mode, title, hint, text)
	C_Timer.After(0, function()
		self.mode, self.exportText = mode, text
		self.title:SetText(title)
		self.hint:SetText(hint)
		self.action:SetShown(mode == "import")
		self.close:ClearAllPoints()
		self.close:SetPoint("BOTTOM", mode == "import" and 56 or 0, 14)
		self.box:SetText(text or "")
		self:Show()
	end)
end

-- If anything still gets blocked, say which function it was.
local blockWatch = CreateFrame("Frame")
blockWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatch:SetScript("OnEvent", function(_, event, addon, fn)
	if addon == ADDON then Print(("%s: the game blocked %s"):format(event, tostring(fn))) end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function OnOff(v) return v and "|cff55ff55on|r" or "|cffff5555off|r" end

local function Help()
	Print("commands:")
	Print("  /xbars unlock | lock  - move the bars")
	Print("  /xbars mode auto | always  - auto = only while Gamepad UI is on")
	Print("  /xbars bar <1-5> on | off  - 1 main, 2 bottom left, 3 bottom right, 4 right, 5 right 2")
	Print("  /xbars cols <1-5> <1-12>  - buttons per row")
	Print("  /xbars scale <0.5-2>   /xbars alpha <0.1-1>")
	Print("  /xbars empty on | off  - show empty slots")
	Print("  /xbars hotkeys on | off  - show keyboard binding text")
	Print("  /xbars status | reset")
	Print("  /xbars export | import  - copy the bar settings to another character")
end

local function Status()
	local active, known = GamepadUIActive()
	Print("Gamepad UI: " .. (known and OnOff(active) or "unknown (InputUtil.IsGamepadUIEnabled not found - bars always shown)"))
	Print("mode " .. db.mode .. ", scale " .. db.scale .. ", alpha " .. db.alpha ..
		", empty " .. OnOff(db.showEmpty) .. ", hotkeys " .. OnOff(db.hotkeys))
	for i, def in ipairs(BAR_DEFS) do
		Print(("  %d %s: %s, %d per row"):format(i, def.label, OnOff(db.bars[i].enabled), db.bars[i].cols))
	end
end

local SAVING_COMMANDS = {
	mode = true, bar = true, cols = true, scale = true, alpha = true,
	empty = true, hotkeys = true, reset = true,
}

SLASH_XANABARS1 = "/xbars"
SlashCmdList.XANABARS = function(msg)
	if not header then return end
	local cmd, a, b = strsplit(" ", strlower(strtrim(msg or "")))
	if cmd == "unlock" then
		SetLocked(false)
	elseif cmd == "lock" then
		SetLocked(true)
	elseif cmd == "mode" and (a == "auto" or a == "always") then
		db.mode = a
		ApplyAll()
		Print("mode: " .. a)
	elseif cmd == "bar" and db.bars[tonumber(a) or 0] and (b == "on" or b == "off") then
		db.bars[tonumber(a)].enabled = (b == "on")
		ApplyAll()
		Print(BAR_DEFS[tonumber(a)].label .. ": " .. OnOff(b == "on"))
	elseif cmd == "cols" and db.bars[tonumber(a) or 0] and tonumber(b) then
		db.bars[tonumber(a)].cols = math.max(1, math.min(12, math.floor(tonumber(b))))
		ApplyAll()
	elseif cmd == "scale" and tonumber(a) then
		db.scale = math.max(0.5, math.min(2, tonumber(a)))
		ApplyAll()
	elseif cmd == "alpha" and tonumber(a) then
		db.alpha = math.max(0.1, math.min(1, tonumber(a)))
		ApplyAll()
	elseif cmd == "empty" and (a == "on" or a == "off") then
		db.showEmpty = (a == "on")
		RefreshButtons()
	elseif cmd == "hotkeys" and (a == "on" or a == "off") then
		db.hotkeys = (a == "on")
		RefreshButtons()
	elseif cmd == "status" then
		Status()
	elseif cmd == "export" then
		dialog:Open("export", "Export bar settings",
			"Click the box, then press Ctrl+C. Paste it into /xbars import on another character.",
			EXPORT_PREFIX .. Base64Encode(SettingsData()))
	elseif cmd == "import" then
		dialog:Open("import", "Import bar settings",
			"Click the box and paste an export string with Ctrl+V. It replaces all current bar settings.")
	elseif cmd == "reset" then
		XanaBarsDB = nil
		InitDB()
		ApplyAll()
		Print("settings reset.")
	else
		Help()
	end
	if SAVING_COMMANDS[cmd] then SaveSettings() end
	if InCombatLockdown() and next(pending) then
		Print("in combat - the change will apply when combat ends.")
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Runs once, as soon as the player's macros are known to be loaded.
local function OnMacrosReady()
	if macrosReady then return end
	macrosReady = true
	if LoadSettingsMacro() then ApplyAll() end
	if saveWanted then
		saveWanted = nil
		SaveSettings()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		InitDB()
		if not CreateBars() then return end
		local accountMacros, characterMacros = GetNumMacros()
		if (accountMacros or 0) + (characterMacros or 0) > 0 then OnMacrosReady() end
		ApplyAll()

		for _, e in ipairs({
			"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
			"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
			"UPDATE_SHAPESHIFT_FORM", "UPDATE_BINDINGS", "ACTIONBAR_SHOWGRID", "ACTIONBAR_HIDEGRID",
			"UPDATE_MACROS",
		}) do
			pcall(self.RegisterEvent, self, e)
		end

		-- The Gamepad UI can be toggled from the options menu at any time.
		C_Timer.NewTicker(1, function()
			if not InCombatLockdown() and header:IsShown() ~= ShouldShow() then
				ApplyAll()
			end
		end)
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		local queue = pending
		pending = {}
		for _, fn in pairs(queue) do fn() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		StopDrag()
		if unlocked then -- bars can't be moved in combat
			unlocked = false
			UpdateMovers()
			Print("Combat started - bars locked.")
		end
	elseif event == "ACTIONBAR_SHOWGRID" then
		gridShown = true
	elseif event == "ACTIONBAR_HIDEGRID" then
		gridShown = false
	elseif event == "UPDATE_MACROS" then
		OnMacrosReady()
		return
	elseif event == "PLAYER_ENTERING_WORLD" then
		ApplyAll()
		-- Fallback for a player with no macros at all, where no macro event may come.
		C_Timer.After(2, OnMacrosReady)
	end
	RefreshButtons()
	C_Timer.After(0.1, RefreshButtons)
end)
