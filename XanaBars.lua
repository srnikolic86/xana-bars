-- XanaBars
-- Fixed action bar layout for WoW Forever's Gamepad UI. The bars are the addon's
-- own secure buttons built on Blizzard's ActionBarButtonTemplate, so they do not
-- touch or re-show the Blizzard bars that the Gamepad UI hides.
--
--   Bottom row always shown at the bottom centre, just above the XP bar: the
--              player's own list of spells, items and macros (not an action bar),
--              plus a button holding the addons' minimap icons. It fades with
--              the Gamepad UI's bar while F1-F4 is held.
--   Bars 1-4   hidden; holding F1-F4 shows bar 1-4 at the bottom centre, in the
--              gamepad layout on a solid dark gray background. A secure snippet
--              does the show/hide, so it works in combat.
--   Edit mode  /xbars edit shows bars 1-4 together in a 2x2 grid near the top of
--              the screen so spells can be dragged onto them, and makes the
--              bottom row editable.

local ADDON = ...
local NUM_BUTTONS = 12

local BAR_DEFS = {
	{ label = "Main bar",         paged = true, binding = "ACTIONBUTTON%d",         holdKey = "F1" },
	{ label = "Bottom left bar",  page = 6,     binding = "MULTIACTIONBAR1BUTTON%d", holdKey = "F2" },
	{ label = "Bottom right bar", page = 5,     binding = "MULTIACTIONBAR2BUTTON%d", holdKey = "F3" },
	{ label = "Right bar",        page = 3,     binding = "MULTIACTIONBAR3BUTTON%d", holdKey = "F4" },
}
local NUM_HOLD_BARS = #BAR_DEFS

-- Gamepad layout: button i goes to PAD_SLOTS[i] = { column, row } on a grid of
-- button-sized cells, row 0 at the top. The D-pad cross is on the left, the
-- face-button cross on the right, a shoulder above each outer corner, and
-- buttons 11 and 12 side by side, centred between the shoulders:
--   LS  .  . 11 12  .  .  RS
--    .  U  .  .  .  U  .
--    L  .  R  .  L  .  R
--    .  D  .  .  .  D  .
local PAD_SLOTS = {
	{ 0, 0 }, -- 1  left shoulder
	{ 1, 3 }, -- 2  D-pad down
	{ 0, 2 }, -- 3  D-pad left
	{ 1, 1 }, -- 4  D-pad up
	{ 2, 2 }, -- 5  D-pad right
	{ 5, 3 }, -- 6  face down
	{ 4, 2 }, -- 7  face left
	{ 5, 1 }, -- 8  face up
	{ 6, 2 }, -- 9  face right
	{ 6, 0 }, -- 10 right shoulder
	{ 2.5, 0 }, -- 11 centre, left
	{ 3.5, 0 }, -- 12 centre, right
}
local PAD_COLS, PAD_ROWS = 7, 4

local BG_INSET = 12                       -- how far the panel reaches past the buttons
local BG_COLOR = { 0.12, 0.12, 0.12, 1 }  -- solid dark gray
local EDGE_COLOR = { 0.35, 0.35, 0.35, 1 } -- fallback edge when the client has no backdrops

-- Panels use Blizzard's dialog border (the grey stone frame of the classic dialog
-- boxes) around a solid dark gray fill. BackdropTemplate where the client has it,
-- the old built-in SetBackdrop otherwise, plain textures as a last resort.
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local PANEL_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = false, edgeSize = 24,
	insets = { left = 7, right = 7, top = 7, bottom = 7 },
}
local BANNER_TEXTURE = "Interface\\DialogFrame\\UI-DialogBox-Header"

-- While a held bar is up, the Gamepad UI's own bars fade to this alpha.
local FADE_ALPHA = 0.15
local FADE_SPEED = 8      -- alpha change per second (1 -> 0.15 in about 0.1 s)
-- The Gamepad UI frames that fade, by global name.
local FADE_FRAMES = { "GamepadMainActionBarFrame" }

local ROW_SIZE = 36                     -- bottom row button size (same as an action button)
local ROW_SPACING = 4                   -- gap between the bottom row's buttons
local ROW_POINT = { "BOTTOM", "BOTTOM", 0, 26 } -- above the XP bar, room for the panel border
local OLD_BAR5_SLOTS = { 37, 48 }       -- action slots of the old bar 5, copied once into the row

local HOLD_POINT = { "BOTTOM", "BOTTOM", 0, 40 } -- where a held bar appears

local EDIT_TOP = -120 -- top edge of the edit-mode grid, from the top of the screen
local EDIT_GAP = 50   -- space between the bars in the edit-mode grid (room for the banners)

local header
local bars = {}
local holders = {}
local allButtons = {}
local editMode = false
local row        -- the bottom row frame
local UpdateFade -- defined with the fading code below
local LayoutRow  -- defined with the bottom row below

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
-- Hotkey text
---------------------------------------------------------------------------
local function UpdateHotkey(btn)
	local hk = btn.HotKey or (btn:GetName() and _G[btn:GetName() .. "HotKey"])
	if not hk then return end
	local key = btn.padBinding and GetBindingKey(btn.padBinding)
	if key then
		hk:SetText(GetBindingText(key, 1))
		hk:Show()
	else
		hk:SetText("")
	end
end

local function RefreshButtons()
	for _, btn in ipairs(allButtons) do
		btn:SetAlpha(1)
		UpdateHotkey(btn)
	end
end

---------------------------------------------------------------------------
-- Layout (protected, so always routed through AfterCombat)
---------------------------------------------------------------------------
local function ButtonSize(bar)
	local size = bar.buttons[1]:GetWidth()
	if not size or size < 10 then size = 36 end
	return size
end

local function LayoutPad(bar)
	local size = ButtonSize(bar)
	for i, btn in ipairs(bar.buttons) do
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD_SLOTS[i][1] * size, -PAD_SLOTS[i][2] * size)
	end
	bar:SetSize(PAD_COLS * size, PAD_ROWS * size)
end

-- Edit mode grid: 1 upper left, 2 upper right, 3 lower left, 4 lower right,
-- centred horizontally near the top of the screen.
local function EditPoint(index, bar)
	local w, h = bar:GetWidth() + 2 * BG_INSET, bar:GetHeight() + 2 * BG_INSET
	local col, row = (index - 1) % 2, math.floor((index - 1) / 2)
	local x = (col == 0) and -(EDIT_GAP / 2 + w / 2) or (EDIT_GAP / 2 + w / 2)
	local y = EDIT_TOP - BG_INSET - row * (h + EDIT_GAP)
	return "TOP", "TOP", x, y
end

local function ApplyAll()
	AfterCombat("apply", function()
		for i, bar in ipairs(bars) do
			bar:ClearAllPoints()
			LayoutPad(bar)
			if editMode then
				local p, rp, x, y = EditPoint(i, bar)
				bar:SetPoint(p, UIParent, rp, x, y)
			else
				bar:SetPoint(HOLD_POINT[1], UIParent, HOLD_POINT[2], HOLD_POINT[3], HOLD_POINT[4])
			end
			bar.banner:SetShown(editMode)
			bar:SetShown(editMode)
		end
		LayoutRow()
		for _, holder in ipairs(holders) do
			holder:SetAttribute("editmode", editMode or nil)
		end
		RefreshButtons()
		UpdateFade()
	end)
end

local function SetEditMode(on)
	if on == editMode then return end
	if on and InCombatLockdown() then
		Print("Can't enter edit mode in combat.")
		return
	end
	editMode = on
	ApplyAll()
	Print(on and ("Edit mode on - drag spells onto bars 1-4, and spells, items or macros onto the " ..
			"bottom row (drag off to move, right-click removes). /xbars edit again when done.")
		or "Edit mode off - hold F1-F4 to show bars 1-4.")
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
		-- Paging uses a plain attribute driver: with a button ID > 0 the Blizzard
		-- template computes slot = ID + (actionpage-1)*12.
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
	-- the mode tries to bind a nil action and errors in Blizzard's BindingUtil.
	btn.commandName = btn.padBinding
	if btn.UpdateHotkeys then
		hooksecurefunc(btn, "UpdateHotkeys", UpdateHotkey)
	end
	btn:Show()
	return btn
end

-- Panel behind a bar's buttons: solid dark gray inside the stone dialog border.
local function CreateBackground(bar)
	local panel = CreateFrame("Frame", nil, bar, BACKDROP_TEMPLATE)
	panel:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	panel:SetPoint("TOPLEFT", -BG_INSET, BG_INSET)
	panel:SetPoint("BOTTOMRIGHT", BG_INSET, -BG_INSET)
	bar.panel = panel

	if panel.SetBackdrop then
		panel:SetBackdrop(PANEL_BACKDROP)
		panel:SetBackdropColor(unpack(BG_COLOR))
		return
	end

	-- No backdrops on this client: flat fill with a 1-pixel edge.
	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(unpack(BG_COLOR))
	local function Thickness(tex, horizontal)
		if PixelUtil and PixelUtil.SetHeight then
			if horizontal then PixelUtil.SetHeight(tex, 1) else PixelUtil.SetWidth(tex, 1) end
		elseif horizontal then tex:SetHeight(1) else tex:SetWidth(1) end
	end
	for _, e in ipairs({
		{ "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
	}) do
		local tex = panel:CreateTexture(nil, "BORDER")
		tex:SetColorTexture(unpack(EDGE_COLOR))
		tex:SetPoint(e[1])
		tex:SetPoint(e[2])
		Thickness(tex, e[3])
	end
end

-- Edit-mode title: the dialog-box banner, resting on the panel's top edge. The
-- banner art fills the top ~40 units of its 64-unit texture, so raising it 38
-- keeps it clear of buttons 11 and 12 in the top middle of the bar.
local function CreateBanner(bar, text)
	local banner = CreateFrame("Frame", nil, bar)
	banner:SetFrameLevel(bar.panel:GetFrameLevel() + 1)
	banner:SetSize(256, 64)
	banner:SetPoint("TOP", bar.panel, "TOP", 0, 38)
	local tex = banner:CreateTexture(nil, "ARTWORK")
	tex:SetTexture(BANNER_TEXTURE)
	tex:SetAllPoints()
	local label = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOP", banner, "TOP", 0, -14)
	label:SetText(text)
	banner:Hide()
	bar.banner = banner
end

---------------------------------------------------------------------------
-- Fading the Gamepad UI's own bars, and the bottom row, while a held bar is up. Only alpha changes,
-- which is allowed in combat. While a key is held the alpha is set again every
-- frame, in case Blizzard's code sets it too.
---------------------------------------------------------------------------
local fadeBase = {}            -- frame -> its alpha before the fade started
local fadeLevel, fadeHeld = 1, false

-- The fading frames that exist right now.
local function GamepadFrames()
	local frames = {}
	for _, name in ipairs(FADE_FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" and frame.SetAlpha then frames[#frames + 1] = frame end
	end
	if row then frames[#frames + 1] = row end -- the bottom row fades too
	return frames
end

local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self, elapsed)
	local target, step = fadeHeld and FADE_ALPHA or 1, elapsed * FADE_SPEED
	if fadeLevel < target then
		fadeLevel = math.min(target, fadeLevel + step)
	else
		fadeLevel = math.max(target, fadeLevel - step)
	end
	for frame, alpha in pairs(fadeBase) do pcall(frame.SetAlpha, frame, alpha * fadeLevel) end
	if not fadeHeld and fadeLevel == 1 then
		wipe(fadeBase)
		self:Hide()
	end
end)

function UpdateFade()
	local held = false
	if not editMode then
		for i = 1, NUM_HOLD_BARS do
			if bars[i] and bars[i]:IsShown() then held = true end
		end
	end
	if held and not next(fadeBase) then
		for _, frame in ipairs(GamepadFrames()) do
			local ok, alpha = pcall(frame.GetAlpha, frame)
			fadeBase[frame] = ok and alpha or 1
		end
	end
	fadeHeld = held
	if next(fadeBase) then fader:Show() end
end

-- For the /xbars frames all diagnostic: calls fn(frame, name) for every named
-- frame. Forbidden frames (the store and other Blizzard-only UI) throw on any
-- method call except IsForbidden, and some frames on this client return a name
-- that isn't a plain string, so both are skipped, and fn runs under pcall.
local function EachNamedFrame(fn)
	local frame = EnumerateFrames()
	while frame do
		if not (frame.IsForbidden and frame:IsForbidden()) then
			local ok, name = pcall(frame.GetName, frame)
			if ok and type(name) == "string" and not string.find(name, "^Xana") then
				pcall(fn, frame, name)
			end
		end
		frame = EnumerateFrames(frame)
	end
end

-- The frame's bottom edge in UIParent units, or nil if it has no position.
local function BottomInUI(frame)
	local ok, bottom, scale = pcall(function() return frame:GetBottom(), frame:GetEffectiveScale() end)
	if ok and bottom and scale then return bottom * scale / UIParent:GetEffectiveScale() end
end

-- Gives a bottom-row button the action-button look: trimmed icon, the default
-- action-button frame, the square highlight, the pushed look and a count.
local function StyleSlot(btn)
	btn:SetSize(ROW_SIZE, ROW_SIZE)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints()
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local frameTex = btn:CreateTexture(nil, "OVERLAY", nil, -1)
	frameTex:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	frameTex:SetPoint("CENTER")
	frameTex:SetSize(ROW_SIZE * 66 / 36, ROW_SIZE * 66 / 36)
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	btn.count:SetPoint("BOTTOMRIGHT", -2, 2)
end

---------------------------------------------------------------------------
-- Minimap button collector. One extra button at the right end of the bottom
-- row opens a panel above it holding the icons that addons put on the minimap;
-- those icons are moved off the minimap into it. Nothing here is protected, so
-- it all works in combat. Being a child of the row, it fades with it.
--
-- Which buttons are taken:
--   * every LibDBIcon button (the library most addons use for minimap icons)
--   * any other named, unprotected Button on Minimap / MinimapBackdrop whose
--     global name was set by an addon (issecurevariable says so - Blizzard's own
--     minimap buttons are secure and stay put), at least 20 units tall (map pins
--     are smaller), and not a HereBeDragons map pin.
---------------------------------------------------------------------------
local COLLECTOR_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local FLYOUT_CELL = 36      -- one grid cell in the panel
local FLYOUT_ROWS = 8       -- buttons per column before a new column starts (to the left)
local FLYOUT_PAD = 12       -- panel padding (clears the border)
local MIN_BUTTON_HEIGHT = 20

local FrameMethods = getmetatable(CreateFrame("Button")).__index
local RawSetPoint, RawClearAllPoints = FrameMethods.SetPoint, FrameMethods.ClearAllPoints
local RawSetParent = FrameMethods.SetParent
local function Noop() end

local collector, flyout
local collected = {}        -- button -> true
local collectedList = {}    -- in the order they were taken

local function IsMapPin(frame)
	local hbd = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
	return hbd and hbd.minimapPins and hbd.minimapPins[frame] ~= nil
end

local function IsAddonMinimapButton(frame)
	if frame.IsForbidden and frame:IsForbidden() then return false end
	if frame:IsProtected() or frame:GetObjectType() ~= "Button" then return false end
	local name = frame:GetName()
	if type(name) ~= "string" or name:find("^Xana") then return false end
	if name:find("^LibDBIcon") then return true end
	local ok, secure = pcall(issecurevariable, name)
	if not ok or secure then return false end
	if (frame:GetHeight() or 0) < MIN_BUTTON_HEIGHT then return false end
	return not IsMapPin(frame)
end

local LayoutFlyout -- below

-- Puts a taken button above the panel. LibDBIcon pins its buttons to MEDIUM
-- strata with SetFixedFrameStrata/SetFixedFrameLevel, which makes plain
-- SetFrameStrata/SetFrameLevel calls do nothing - and the panel (DIALOG) would
-- then cover them. So unpin, set, and pin again so the addon can't change it.
local function RaiseButton(btn)
	if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
	if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
	btn:SetFrameStrata(flyout:GetFrameStrata())
	btn:SetFrameLevel(flyout:GetFrameLevel() + 2)
	if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(true) end
	if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(true) end
end

-- Moves one button into the panel and stops its addon from moving it back:
-- SetPoint, ClearAllPoints and SetParent become no-ops on that button (the panel
-- uses the real methods), and dragging is turned off.
local function Collect(btn)
	if collected[btn] then return end
	collected[btn] = true
	collectedList[#collectedList + 1] = btn
	btn.SetPoint, btn.ClearAllPoints, btn.SetParent = Noop, Noop, Noop
	btn:SetScript("OnDragStart", nil)
	btn:SetScript("OnDragStop", nil)
	RawSetParent(btn, flyout)
	RaiseButton(btn)
	btn:SetAlpha(1)
	-- An addon showing or hiding its icon (e.g. from its own options) re-lays out the panel.
	btn:HookScript("OnShow", function() LayoutFlyout() end)
	btn:HookScript("OnHide", function() LayoutFlyout() end)
	-- Clicking an icon closes the panel. On the next frame, so the addon's own
	-- click handling (which may open a window or menu) has finished first.
	btn:HookScript("OnClick", function() C_Timer.After(0, function() flyout:Hide() end) end)
end

local function ScanMinimapButtons()
	if not collector then return end
	local before = #collectedList
	local lib = LibStub and LibStub("LibDBIcon-1.0", true)
	if lib and lib.objects then
		for _, btn in pairs(lib.objects) do pcall(Collect, btn) end
	end
	for _, parent in ipairs({ Minimap or false, MinimapBackdrop or false }) do
		if parent then
			for _, child in ipairs({ parent:GetChildren() }) do
				local ok, take = pcall(IsAddonMinimapButton, child)
				if ok and take then pcall(Collect, child) end
			end
		end
	end
	if #collectedList ~= before then LayoutFlyout() end
end

-- Shown buttons go bottom to top in columns of FLYOUT_ROWS, the first column at
-- the right (over the collector), further columns to the left.
function LayoutFlyout()
	local shown = {}
	for _, btn in ipairs(collectedList) do
		if btn:IsShown() then shown[#shown + 1] = btn end
	end
	local n = #shown
	local rows = math.max(1, math.min(n, FLYOUT_ROWS))
	local cols = math.max(1, math.ceil(n / FLYOUT_ROWS))
	for i, btn in ipairs(shown) do
		local col, row = math.floor((i - 1) / FLYOUT_ROWS), (i - 1) % FLYOUT_ROWS
		pcall(RaiseButton, btn)
		btn:SetAlpha(1)
		RawClearAllPoints(btn)
		RawSetPoint(btn, "CENTER", flyout, "BOTTOMRIGHT",
			-(FLYOUT_PAD + col * FLYOUT_CELL + FLYOUT_CELL / 2), FLYOUT_PAD + row * FLYOUT_CELL + FLYOUT_CELL / 2)
	end
	flyout:SetSize(cols * FLYOUT_CELL + 2 * FLYOUT_PAD, rows * FLYOUT_CELL + 2 * FLYOUT_PAD)
	flyout.empty:SetShown(n == 0)
	collector.count:SetText(n > 0 and n or "")
end

-- Placed by LayoutRow, in the row's last cell.
local function CreateCollector(parent)
	collector = CreateFrame("Button", "XanaBarsMinimapButtons", parent)
	StyleSlot(collector)
	collector.icon:SetTexture(COLLECTOR_ICON)
	collector:RegisterForClicks("LeftButtonUp")

	flyout = CreateFrame("Frame", "XanaBarsMinimapFlyout", collector, BACKDROP_TEMPLATE)
	flyout:SetPoint("BOTTOMRIGHT", collector, "TOPRIGHT", FLYOUT_PAD, BG_INSET)
	flyout:SetFrameStrata("DIALOG")
	flyout:EnableMouse(true)
	flyout:Hide()
	if flyout.SetBackdrop then
		flyout:SetBackdrop(PANEL_BACKDROP)
		flyout:SetBackdropColor(unpack(BG_COLOR))
	else
		local bg = flyout:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(unpack(BG_COLOR))
	end
	flyout.empty = flyout:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	flyout.empty:SetPoint("CENTER")
	flyout.empty:SetText("None")

	collector:SetScript("OnClick", function()
		if not flyout:IsShown() then ScanMinimapButtons() LayoutFlyout() end
		flyout:SetShown(not flyout:IsShown())
	end)
	collector:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Minimap buttons")
		GameTooltip:AddLine("Click to show or hide the addon icons from the minimap.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	collector:SetScript("OnLeave", function() GameTooltip:Hide() end)

	LayoutFlyout()
	-- Addons create their icons at different times (some only after login), so
	-- keep looking. Only Minimap's direct children are read, which is cheap.
	C_Timer.NewTicker(5, ScanMinimapButtons)
end

---------------------------------------------------------------------------
-- Bottom row: the player's own list of spells, items and macros, with the
-- minimap-button collector in its last cell. It is not an action bar: the
-- addon keeps the list itself, and its buttons are SecureActionButtons that
-- cast the entry directly, so they work in combat. /xbars edit swaps in plain
-- editor buttons in the same place, plus a "+" slot, that take drops.
---------------------------------------------------------------------------
local entries = {}       -- { kind = "spell" | "item" | "macro", id = number, name = string }
local rowButtons = {}    -- secure cast buttons, by position
local editButtons = {}   -- edit-mode buttons, by position

---------------------------------------------------------------------------
-- Storage. The Forever client writes SavedVariables but never loads them, so
-- the list lives in a character-specific macro named "XanaBars" whose body is
-- a no-op data line (found by the line, not the name):
--   /xbdata 2|<entry>,<entry>,...
--   <entry> = s<spellID> | i<itemID> | m<macro name, with % , | and newline as %XX>
-- Data from before 2.4.0 ("/xbdata 1|...", the old layout settings) holds no
-- list; it is overwritten on the first save.
---------------------------------------------------------------------------
local MACRO_NAME, DATA_TAG = "XanaBars", "/xbdata "
local MACRO_LIMIT = 255
local MACRO_SCAN_END = 300  -- beyond the last possible macro index on any client
local macrosReady, saveWanted, warnedMacro, listLoaded

-- Clicking the macro does nothing.
SLASH_XANABARSDATA1 = "/xbdata"
SlashCmdList.XANABARSDATA = function() end

-- Only character macros count: account macros fill 1..numAccount with no gaps.
local function FindDataMacro()
	for i = (GetNumMacros() or 0) + 1, MACRO_SCAN_END do
		local name, _, body = GetMacroInfo(i)
		if name and body and body:find(DATA_TAG, 1, true) then return i end
	end
end

local function Escape(s)
	return (s:gsub("[%%,|\n]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function Unescape(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function DataLine(list)
	local parts = {}
	for i, e in ipairs(list) do
		parts[i] = (e.kind == "spell" and ("s" .. e.id)) or (e.kind == "item" and ("i" .. e.id))
			or ("m" .. Escape(e.name))
	end
	return DATA_TAG .. "2|" .. table.concat(parts, ",")
end

-- The list in a macro body, or nil if it holds none.
local function ParseData(body)
	local version, rest = (body or ""):match("/xbdata (%d+)|([^\n]*)")
	if version ~= "2" then return nil end
	local list = {}
	for field in rest:gmatch("[^,]+") do
		local k, v = field:sub(1, 1), field:sub(2)
		if k == "s" and tonumber(v) then list[#list + 1] = { kind = "spell", id = tonumber(v) }
		elseif k == "i" and tonumber(v) then list[#list + 1] = { kind = "item", id = tonumber(v) }
		elseif k == "m" and v ~= "" then list[#list + 1] = { kind = "macro", name = Unescape(v) } end
	end
	return list
end

-- Macros can't be edited in combat, and must not be written before the existing
-- ones have loaded (or a second data macro would be created).
local function SaveList()
	if InCombatLockdown() then AfterCombat("save", SaveList) return end
	if not macrosReady then saveWanted = true return end
	local body = DataLine(entries)
	local index = FindDataMacro()
	if index then
		local _, _, old = GetMacroInfo(index)
		if old ~= body then EditMacro(index, nil, nil, body) end
		return
	end
	local ok, created = pcall(CreateMacro, MACRO_NAME, 134400, body, true)
	if (not ok or not created or created == 0) and not warnedMacro then
		warnedMacro = true
		Print("Couldn't create the XanaBars macro (are this character's macro slots full?). " ..
			"The bottom row won't survive a logout until one is free.")
	end
end

---------------------------------------------------------------------------
-- Entry details
---------------------------------------------------------------------------
local function EntryIcon(e)
	if e.kind == "spell" then
		return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.id))
			or (GetSpellTexture and GetSpellTexture(e.id))
	elseif e.kind == "item" then
		return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id))
			or (GetItemIcon and GetItemIcon(e.id))
	else
		local _, icon = GetMacroInfo(e.name)
		return icon
	end
end

local function ItemCount(id)
	local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
	return fn and fn(id) or 0
end

local function SpellCooldown(id)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(id)
		if type(info) == "table" then return info.startTime, info.duration end
	end
	if GetSpellCooldown then
		local start, duration = GetSpellCooldown(id)
		return start, duration
	end
end

local function EntryCooldown(e)
	if e.kind == "spell" then return SpellCooldown(e.id) end
	if e.kind == "item" then
		local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
		if fn then
			local start, duration = fn(e.id)
			return start, duration
		end
	elseif GetMacroSpell then
		local spell = GetMacroSpell(e.name)
		if type(spell) == "number" then return SpellCooldown(spell) end
	end
end

local function PickupEntry(e)
	if e.kind == "spell" then
		local fn = (C_Spell and C_Spell.PickupSpell) or PickupSpell
		if fn then fn(e.id) end
	elseif e.kind == "item" then
		local fn = (C_Item and C_Item.PickupItem) or PickupItem
		if fn then fn(e.id) end
	else
		PickupMacro(e.name)
	end
end

local function ShowEntryTooltip(btn, e, hint)
	GameTooltip:SetOwner(btn, "ANCHOR_TOP")
	if not e then
		GameTooltip:SetText("Empty slot")
	elseif e.kind == "spell" then
		GameTooltip:SetSpellByID(e.id)
	elseif e.kind == "item" then
		GameTooltip:SetItemByID(e.id)
	else
		GameTooltip:SetText(e.name)
	end
	if hint then GameTooltip:AddLine(hint, 0.6, 0.8, 1, true) end
	GameTooltip:Show()
end

local function SlotVisual(btn, e)
	if not e then
		btn.icon:SetColorTexture(0.06, 0.05, 0.04, 0.85)
		btn.icon:SetDesaturated(false)
		btn.count:SetText("")
		return
	end
	btn.icon:SetTexture(EntryIcon(e) or 134400)
	local count = e.kind == "item" and ItemCount(e.id)
	btn.count:SetText((count and count > 1) and count or "")
	btn.icon:SetDesaturated(count == 0)
end

-- Icons, counts and cooldowns. Not protected, so any time.
local function RefreshRow()
	for i, btn in ipairs(rowButtons) do
		local e = entries[i]
		if e and btn:IsShown() then
			pcall(SlotVisual, btn, e)
			local ok, start, duration = pcall(EntryCooldown, e)
			if ok and start and duration and duration > 0 then
				btn.cooldown:SetCooldown(start, duration)
			else
				btn.cooldown:SetCooldown(0, 0)
			end
		end
	end
	for i, btn in ipairs(editButtons) do
		if btn:IsShown() then pcall(SlotVisual, btn, entries[i]) end
	end
end

local refreshQueued
local function QueueRefreshRow()
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, function() refreshQueued = nil RefreshRow() end)
end

---------------------------------------------------------------------------
-- Editing (edit mode only, so never in combat)
---------------------------------------------------------------------------
local function RowChanged()
	SaveList()
	LayoutRow()
end

-- What is on the cursor as an entry; false if it is something the row can't hold.
local function CursorEntry()
	local kind, a, _, c = GetCursorInfo()
	if kind == "spell" and (c or a) then return { kind = "spell", id = c or a } end
	if kind == "item" and a then return { kind = "item", id = a } end
	if kind == "macro" and a then
		local name = GetMacroInfo(a)
		if name then return { kind = "macro", name = name } end
	end
	if kind then return false end
end

-- Drops the cursor's contents at position i (past the end appends). Dropping on
-- an entry replaces it and puts the old one on the cursor, as action bars do.
local function DropOn(i)
	if InCombatLockdown() then return end
	local e = CursorEntry()
	if e == nil then return end
	if e == false then
		Print("Only spells, items and macros can go on the bottom row.")
		return
	end
	if i > #entries then i = #entries + 1 end
	local old = entries[i]
	entries[i] = e
	if #DataLine(entries) > MACRO_LIMIT then
		entries[i] = old
		Print("The bottom row is full: that's all that fits in a 255-character macro.")
		return
	end
	ClearCursor()
	if old then pcall(PickupEntry, old) end
	RowChanged()
end

local function RemoveAt(i)
	if InCombatLockdown() or not entries[i] then return end
	table.remove(entries, i)
	RowChanged()
end

local function PickUpAt(i)
	local e = entries[i]
	if InCombatLockdown() or not e or GetCursorInfo() then return end
	table.remove(entries, i)
	pcall(PickupEntry, e)
	RowChanged()
end

---------------------------------------------------------------------------
-- Buttons and layout
---------------------------------------------------------------------------
local function RowButton(i)
	if rowButtons[i] then return rowButtons[i] end
	local btn = CreateFrame("Button", "XanaBarsRowButton" .. i, row, "SecureActionButtonTemplate")
	StyleSlot(btn)
	btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
	btn.cooldown:SetAllPoints(btn.icon)
	-- Same click registration as the action buttons (see CreateButton).
	if C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("ActionButtonUseKeyDown") ~= nil then
		btn:RegisterForClicks("AnyDown", "AnyUp")
	else
		btn:RegisterForClicks("AnyUp")
	end
	btn:SetScript("OnEnter", function(self) pcall(ShowEntryTooltip, self, entries[i]) end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rowButtons[i] = btn
	return btn
end

local function EditButton(i)
	if editButtons[i] then return editButtons[i] end
	local btn = CreateFrame("Button", nil, row)
	StyleSlot(btn)
	btn.plus = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	btn.plus:SetPoint("CENTER")
	btn.plus:SetText("+")
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then RemoveAt(i) else DropOn(i) end
	end)
	btn:SetScript("OnReceiveDrag", function() DropOn(i) end)
	btn:SetScript("OnDragStart", function() PickUpAt(i) end)
	btn:SetScript("OnEnter", function(self)
		local e = entries[i]
		pcall(ShowEntryTooltip, self, e, e and "Drag to move. Right-click removes."
			or "Drop a spell, item or macro here.")
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	editButtons[i] = btn
	return btn
end

-- Entries left to right, then (in edit mode) a "+" slot, then the collector.
-- The row holds secure buttons, so layout waits for the end of combat.
function LayoutRow()
	if not row then return end
	AfterCombat("row", function()
		local n = #entries
		local slots = editMode and n + 1 or n
		local step = ROW_SIZE + ROW_SPACING
		for i = 1, math.max(n, #rowButtons) do
			local btn = i <= n and RowButton(i) or rowButtons[i]
			if i <= n then
				local e = entries[i]
				btn:SetAttribute("type", e.kind)
				btn:SetAttribute("spell", e.kind == "spell" and e.id or nil)
				btn:SetAttribute("item", e.kind == "item" and ("item:" .. e.id) or nil)
				btn:SetAttribute("macro", e.kind == "macro" and e.name or nil)
				btn:ClearAllPoints()
				btn:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * step, 0)
			end
			btn:SetShown(i <= n and not editMode)
		end
		for i = 1, math.max(editMode and slots or 0, #editButtons) do
			local btn = (editMode and i <= slots) and EditButton(i) or editButtons[i]
			if editMode and i <= slots then
				btn:ClearAllPoints()
				btn:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * step, 0)
				btn.plus:SetShown(entries[i] == nil)
				btn:Show()
			else
				btn:Hide()
			end
		end
		collector:ClearAllPoints()
		collector:SetPoint("TOPLEFT", row, "TOPLEFT", slots * step, 0)
		row:SetSize((slots + 1) * step - ROW_SPACING, ROW_SIZE)
		row:ClearAllPoints()
		row:SetPoint(ROW_POINT[1], UIParent, ROW_POINT[2], ROW_POINT[3], ROW_POINT[4])
		row.banner:SetShown(editMode)
		RefreshRow()
	end)
end

-- First login with this version: copy what was on the old bar 5's action
-- slots, so nothing is lost. Only when there's no saved list yet.
local function SeedFromOldBar5()
	if listLoaded or #entries > 0 or InCombatLockdown() then return end
	for slot = OLD_BAR5_SLOTS[1], OLD_BAR5_SLOTS[2] do
		local kind, id = GetActionInfo(slot)
		local e
		if kind == "spell" and id then e = { kind = "spell", id = id }
		elseif kind == "item" and id then e = { kind = "item", id = id }
		elseif kind == "macro" and id then
			local name = GetMacroInfo(id)
			if name then e = { kind = "macro", name = name } end
		end
		if e then
			entries[#entries + 1] = e
			if #DataLine(entries) > MACRO_LIMIT then entries[#entries] = nil break end
		end
	end
	if #entries > 0 then
		Print(("Copied %d entries from the old bar 5 onto the bottom row."):format(#entries))
		RowChanged()
	end
end

-- Runs once, as soon as the player's macros are known to be loaded.
local function OnMacrosReady()
	if macrosReady then return end
	macrosReady = true
	if not saveWanted then
		local index = FindDataMacro()
		local list = index and ParseData(select(3, GetMacroInfo(index)))
		if list then
			entries, listLoaded = list, true
			LayoutRow()
		end
	end
	if saveWanted then
		saveWanted = nil
		SaveList()
	end
	if not listLoaded then C_Timer.After(1, SeedFromOldBar5) end
end

local function CreateRow()
	row = CreateFrame("Frame", "XanaBarsRow", header)
	CreateBackground(row)
	CreateBanner(row, "Bottom row")
	CreateCollector(row)
	LayoutRow()
end

-- An invisible secure button that F1-F4 are bound to. Key down shows its bar,
-- key up hides it. The snippet runs in the restricted environment, so it works
-- in combat. In edit mode it does nothing (all bars stay shown).
local function CreateHolder(index, bar)
	local holder = CreateFrame("Button", "XanaBarsHold" .. index, UIParent, "SecureHandlerClickTemplate")
	holder:RegisterForClicks("AnyDown", "AnyUp")
	holder:SetFrameRef("bar", bar)
	holder:SetAttribute("_onclick", [[
		if self:GetAttribute("editmode") then return end
		local bar = self:GetFrameRef("bar")
		if down then bar:Show() else bar:Hide() end
	]])
	SetOverrideBindingClick(holder, false, BAR_DEFS[index].holdKey, holder:GetName(), "LeftButton")
	holders[index] = holder
end

local function CreateBars()
	header = CreateFrame("Frame", "XanaBarsHeader", UIParent)
	header:SetSize(1, 1)
	header:SetPoint("CENTER")

	for barIndex, def in ipairs(BAR_DEFS) do
		-- Protected frame, so the holder snippets may show and hide it in combat.
		local bar = CreateFrame("Frame", "XanaBarsBar" .. barIndex, header, "SecureHandlerBaseTemplate")
		bar.buttons = {}
		bar:SetFrameStrata("HIGH") -- above the Gamepad UI's own bars
		CreateBackground(bar)
		CreateBanner(bar, ("Bar %d (%s)"):format(barIndex, def.holdKey))
		bar:HookScript("OnShow", UpdateFade)
		bar:HookScript("OnHide", UpdateFade)
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
		bar:Hide()
		CreateHolder(barIndex, bar)
	end
	CreateRow()
	return true
end

-- If anything gets blocked, say which function it was.
local blockWatch = CreateFrame("Frame")
blockWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatch:SetScript("OnEvent", function(_, event, addon, fn)
	if addon == ADDON then Print(("%s: the game blocked %s"):format(event, tostring(fn))) end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Help()
	Print("hold F1-F4 to show bars 1-4. The bottom row is always shown.")
	Print("  /xbars edit  - toggle edit mode (bars 1-4 shown, bottom row editable)")
	Print("  /xbars frames  - list the Gamepad UI frames that fade while a bar is held")
end

local function ListFrames()
	Print("These fade while F1-F4 is held:")
	for _, name in ipairs(FADE_FRAMES) do
		local frame = _G[name]
		local found = type(frame) == "table" and frame.SetAlpha
		Print(("  %s - %s"):format(name, found and "found" or "|cffff5555not found|r"))
	end
end

-- Diagnostic: every shown, named frame whose name suggests the Gamepad UI or an
-- action bar, wherever it is, with its bottom edge, so the right ones can be found.
local function ListAllFrames()
	local rows = {}
	EachNamedFrame(function(frame, name)
		local lower = name:lower()
		if lower:find("pad", 1, true) or lower:find("actionbar", 1, true) then
			local ok, shown = pcall(frame.IsVisible, frame)
			if ok and shown then
				local bottom = BottomInUI(frame)
				rows[#rows + 1] = ("%s  (bottom %s)"):format(name, bottom and math.floor(bottom) or "?")
			end
		end
	end)
	table.sort(rows)
	Print(("%d visible frames with 'pad' or 'actionbar' in the name (screen height %d):")
		:format(#rows, math.floor(UIParent:GetHeight())))
	for i = 1, math.min(#rows, 60) do Print("  " .. rows[i]) end
	if #rows > 60 then Print(("  ... and %d more"):format(#rows - 60)) end
end

SLASH_XANABARS1 = "/xbars"
SlashCmdList.XANABARS = function(msg)
	if not header then return end
	local cmd, a = strsplit(" ", strlower(strtrim(msg or "")))
	if cmd == "edit" then
		if a == "on" then SetEditMode(true)
		elseif a == "off" then SetEditMode(false)
		else SetEditMode(not editMode) end
	elseif cmd == "frames" then
		local ok, err = pcall(a == "all" and ListAllFrames or ListFrames)
		if not ok then Print("frames: " .. tostring(err)) end
	else
		Help()
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		if not CreateBars() then return end
		ApplyAll()
		local accountMacros, characterMacros = GetNumMacros()
		if (accountMacros or 0) + (characterMacros or 0) > 0 then OnMacrosReady() end
		for _, e in ipairs({
			"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
			"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
			"UPDATE_SHAPESHIFT_FORM", "UPDATE_BINDINGS", "UPDATE_MACROS",
			"SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE", "SPELLS_CHANGED",
			"GET_ITEM_INFO_RECEIVED",
		}) do
			pcall(self.RegisterEvent, self, e)
		end
		return
	end

	-- Bottom row icons, counts and cooldowns.
	if event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" or event == "BAG_UPDATE"
		or event == "SPELLS_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" then
		QueueRefreshRow()
		return
	elseif event == "UPDATE_MACROS" then
		OnMacrosReady()
		QueueRefreshRow()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		local queue = pending
		pending = {}
		for _, fn in pairs(queue) do fn() end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Protected changes are still allowed while this event runs, so edit mode
		-- can be closed before the lockdown starts.
		if editMode then
			SetEditMode(false)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		ApplyAll()
		C_Timer.After(1, ScanMinimapButtons)
		-- Fallback for a character with no macros at all, where no macro event may come.
		C_Timer.After(2, OnMacrosReady)
	end
	RefreshButtons()
	C_Timer.After(0.1, RefreshButtons)
end)
