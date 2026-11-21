-- XanaBars
-- Fixed action bar layout for WoW Forever's Gamepad UI. The bars are the addon's
-- own secure buttons built on Blizzard's ActionBarButtonTemplate, so they do not
-- touch or re-show the Blizzard bars that the Gamepad UI hides.
--
--   Bar 5      always shown, one vertical column on the right edge of the screen.
--   Bars 1-4   hidden; holding F1-F4 shows bar 1-4 at the bottom centre, in the
--              gamepad layout on a solid dark gray background. A secure snippet
--              does the show/hide, so it works in combat.
--   Edit mode  /xbars edit shows bars 1-4 together in a 2x2 grid near the top of
--              the screen so spells can be dragged onto them.

local ADDON = ...
local NUM_BUTTONS = 12

local BAR_DEFS = {
	{ label = "Main bar",         paged = true, binding = "ACTIONBUTTON%d",         holdKey = "F1" },
	{ label = "Bottom left bar",  page = 6,     binding = "MULTIACTIONBAR1BUTTON%d", holdKey = "F2" },
	{ label = "Bottom right bar", page = 5,     binding = "MULTIACTIONBAR2BUTTON%d", holdKey = "F3" },
	{ label = "Right bar",        page = 3,     binding = "MULTIACTIONBAR3BUTTON%d", holdKey = "F4" },
	{ label = "Right bar 2",      page = 4,     binding = "MULTIACTIONBAR4BUTTON%d" },
}
local NUM_HOLD_BARS = 4  -- bars 1-4 are the held / edit-mode bars
local SIDE_BAR = 5       -- the always-visible vertical bar

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

local BG_INSET = 8                      -- how far the background reaches past the buttons
local BG_COLOR = { 0.12, 0.12, 0.12, 1 } -- solid dark gray
local EDGE_COLOR = { 0.35, 0.35, 0.35, 1 }

local SIDE_SPACING = 4                  -- gap between the side bar's buttons
local SIDE_POINT = { "RIGHT", "RIGHT", -10, 0 }

local HOLD_POINT = { "BOTTOM", "BOTTOM", 0, 40 } -- where a held bar appears

local EDIT_TOP = -90  -- top edge of the edit-mode grid, from the top of the screen
local EDIT_GAP = 30   -- space between the bars in the edit-mode grid (room for labels)

local header
local bars = {}
local holders = {}
local allButtons = {}
local editMode = false

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

local function LayoutColumn(bar)
	local step = ButtonSize(bar) + SIDE_SPACING
	for i, btn in ipairs(bar.buttons) do
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -(i - 1) * step)
	end
	bar:SetSize(step - SIDE_SPACING, NUM_BUTTONS * step - SIDE_SPACING)
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
			if i == SIDE_BAR then
				LayoutColumn(bar)
				bar:SetPoint(SIDE_POINT[1], UIParent, SIDE_POINT[2], SIDE_POINT[3], SIDE_POINT[4])
				bar:Show()
			else
				LayoutPad(bar)
				if editMode then
					local p, rp, x, y = EditPoint(i, bar)
					bar:SetPoint(p, UIParent, rp, x, y)
				else
					bar:SetPoint(HOLD_POINT[1], UIParent, HOLD_POINT[2], HOLD_POINT[3], HOLD_POINT[4])
				end
				bar.label:SetShown(editMode)
				bar:SetShown(editMode)
			end
		end
		for _, holder in ipairs(holders) do
			holder:SetAttribute("editmode", editMode or nil)
		end
		RefreshButtons()
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
	Print(on and "Edit mode on - drag spells onto the bars. /xbars edit again when done."
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

-- Solid dark gray panel with a 1-pixel lighter edge, drawn behind a bar's
-- buttons. Plain textures, not BackdropTemplate, which this client may not have.
local function CreateBackground(bar)
	local bgFrame = CreateFrame("Frame", nil, bar)
	bgFrame:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
	bgFrame:SetPoint("TOPLEFT", -BG_INSET, BG_INSET)
	bgFrame:SetPoint("BOTTOMRIGHT", BG_INSET, -BG_INSET)

	local bg = bgFrame:CreateTexture(nil, "BACKGROUND")
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
		local tex = bgFrame:CreateTexture(nil, "BORDER")
		tex:SetColorTexture(unpack(EDGE_COLOR))
		tex:SetPoint(e[1])
		tex:SetPoint(e[2])
		Thickness(tex, e[3])
	end
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
		if barIndex <= NUM_HOLD_BARS then
			bar:SetFrameStrata("HIGH") -- above the Gamepad UI's own bars
			CreateBackground(bar)
			bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			bar.label:SetPoint("BOTTOM", bar, "TOP", 0, BG_INSET + 4)
			bar.label:SetText(("Bar %d (%s)"):format(barIndex, def.holdKey))
			bar.label:Hide()
		end
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
		if barIndex <= NUM_HOLD_BARS then
			bar:Hide()
			CreateHolder(barIndex, bar)
		end
	end
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
	Print("hold F1-F4 to show bars 1-4. Bar 5 is always shown on the right.")
	Print("  /xbars edit  - toggle edit mode (all four bars shown to drag spells onto)")
end

SLASH_XANABARS1 = "/xbars"
SlashCmdList.XANABARS = function(msg)
	if not header then return end
	local cmd, a = strsplit(" ", strlower(strtrim(msg or "")))
	if cmd == "edit" then
		if a == "on" then SetEditMode(true)
		elseif a == "off" then SetEditMode(false)
		else SetEditMode(not editMode) end
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
		for _, e in ipairs({
			"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
			"ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
			"UPDATE_SHAPESHIFT_FORM", "UPDATE_BINDINGS",
		}) do
			pcall(self.RegisterEvent, self, e)
		end
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
	end
	RefreshButtons()
	C_Timer.After(0.1, RefreshButtons)
end)
