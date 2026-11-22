-- Quest Automator: the stat-profile switcher (SPECS/STAT_PROFILES.md, "Profile switchers
-- outside the settings page"). ONE control in two visual styles:
--
--   "label"  - "Stat profile: Shaman Enhancement v" text row (pick window)
--   "bubble" - a small chrome bubble drawn like the AH score bubble at reduced alpha,
--              showing the short profile name (auction house, left of the search box)
--
-- Click = popup listing Rules.Profiles(class) with a radio mark on the current one
-- (MenuUtil.CreateContextMenu on 11.x clients; a plain button dropdown of our own
-- otherwise). Picking one calls Rules.SelectProfile and then NS.OnSettingsChanged(),
-- whose fan-out re-scores the pick window, repaints the AH rows and refreshes the grid.
--
-- Visibility: settings.profileSwitchers (default on). Players who run one spec can
-- switch the switchers off; the settings-page radio group is unaffected.
local ADDON, NS = ...
local L = NS.L
local Rules = NS.Rules
local ProfileSwitch = {}
NS.ProfileSwitch = ProfileSwitch

ProfileSwitch.BUBBLE_HEIGHT = 16
ProfileSwitch.BUBBLE_PAD = 5
ProfileSwitch.BUBBLE_ALPHA = 0.7     -- chrome, not a score
ProfileSwitch.CHEVRON = " |cff808080v|r"

function ProfileSwitch.Enabled()
	return NS.db and NS.db.settings and NS.db.settings.profileSwitchers ~= false
end

-- "Shaman Enhancement" -> "Enhancement": the class word is redundant where the class
-- is obvious. Custom names are shown as typed.
function ProfileSwitch.ShortName(profile)
	if not profile then return "?" end
	local name = profile.name or "?"
	if profile.builtin then
		local localized = NS.SafeString(select(1, NS.Call("UnitClass", "player")))
		for _, word in ipairs({ localized, profile.class and (profile.class:sub(1, 1) .. profile.class:sub(2):lower()) }) do
			if word and name:sub(1, #word + 1):lower() == (word .. " "):lower() then return name:sub(#word + 2) end
		end
	end
	return name
end

local function Select(id)
	if Rules.SelectProfile(id) then NS.OnSettingsChanged() end
end

-- The popup. MenuUtil where present; else a throwaway frame of buttons anchored to the owner.
local fallbackMenu
local function OpenFallback(owner)
	local class = Rules.Class()
	local list = Rules.Profiles(class)
	local selected = Rules.SelectedProfile(class)
	if not fallbackMenu then
		fallbackMenu = CreateFrame("Frame", "QuestAutomatorProfileMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		fallbackMenu:SetFrameStrata("FULLSCREEN_DIALOG")
		if fallbackMenu.SetBackdrop then
			fallbackMenu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			fallbackMenu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
		end
		fallbackMenu.buttons = {}
		fallbackMenu:SetScript("OnLeave", function(self) if not self:IsMouseOver() then self:Hide() end end)
	end
	local m = fallbackMenu
	local width = 120
	for i, p in ipairs(list) do
		local b = m.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, m)
			b:SetHeight(18)
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", b, "LEFT", 8, 0)
			b.text:SetJustifyH("LEFT")
			local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(b); hl:SetColorTexture(1, 1, 1, 0.08)
			m.buttons[i] = b
		end
		b.profileID = p.id
		b.text:SetText((selected and selected.id == p.id and "|cffffcf4d\226\128\162|r " or "   ") .. p.name)
		width = math.max(width, b.text:GetStringWidth() + 24)
		b:SetScript("OnClick", function(self) Select(self.profileID); m:Hide() end)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -(6 + (i - 1) * 18))
		b:Show()
	end
	for i = #list + 1, #m.buttons do m.buttons[i]:Hide() end
	for i = 1, #list do m.buttons[i]:SetWidth(width - 8) end
	m:SetSize(width, 12 + #list * 18)
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	m:Show()
end

function ProfileSwitch.OpenMenu(owner)
	local class = Rules.Class()
	if MenuUtil and MenuUtil.CreateContextMenu then
		local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
			if root.CreateTitle then root:CreateTitle(L["Stat profile"]) end
			local selected = Rules.SelectedProfile(class)
			for _, p in ipairs(Rules.Profiles(class)) do
				local id = p.id
				root:CreateRadio(p.name, function() return selected and selected.id == id end, function() Select(id) end)
			end
		end)
		if ok then return true end
	end
	OpenFallback(owner)
	return true
end

-- The control. parent: frame to live in. style: "label" | "bubble". Returns a Button
-- with :Update() (re-reads the selected profile and the setting) and :Refresh() alias.
function ProfileSwitch.Create(parent, style)
	local b = CreateFrame("Button", nil, parent, style == "bubble" and BackdropTemplateMixin and "BackdropTemplate" or nil)
	b.style = style
	b.text = b:CreateFontString(nil, "OVERLAY", style == "bubble" and "GameFontHighlightSmall" or "GameFontHighlightSmall")
	if style == "bubble" then
		b:SetHeight(ProfileSwitch.BUBBLE_HEIGHT)
		if b.SetBackdrop then
			b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
			local AS = NS.AuctionScore
			local bg, border = AS and AS.EXACT.bg or { 0.05, 0.25, 0.05, 0.9 }, AS and AS.EXACT.border or { 0.25, 0.8, 0.25, 0.9 }
			b:SetBackdropColor(bg[1], bg[2], bg[3], (bg[4] or 1) * ProfileSwitch.BUBBLE_ALPHA)
			b:SetBackdropBorderColor(border[1], border[2], border[3], (border[4] or 1) * ProfileSwitch.BUBBLE_ALPHA)
		end
		b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
		b.text:SetTextColor(0.7, 0.95, 0.7)
	else
		b:SetHeight(14)
		b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
		b.text:SetTextColor(0.69, 0.69, 0.69)
	end
	b:SetScript("OnClick", function(self) ProfileSwitch.OpenMenu(self) end)
	b:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["Stat profile"], 1, 1, 1)
		local p = Rules.SelectedProfile(Rules.Class())
		if p then GameTooltip:AddLine(p.name, 1, 0.82, 0) end
		GameTooltip:AddLine(L["Click to switch the stat profile this character scores rewards with."], nil, nil, nil, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	function b:Update()
		if not ProfileSwitch.Enabled() then self:Hide(); return false end
		local p = Rules.SelectedProfile(Rules.Class())
		if self.style == "bubble" then
			self.text:SetText(ProfileSwitch.ShortName(p))
			self:SetWidth(math.ceil(self.text:GetStringWidth()) + 2 * ProfileSwitch.BUBBLE_PAD)
		else
			self.text:SetText(string.format(L["Stat profile: %s"], p and p.name or "?") .. ProfileSwitch.CHEVRON)
			self:SetWidth(math.ceil(self.text:GetStringWidth()) + 4)
		end
		self:Show()
		return true
	end
	b.Refresh = b.Update
	return b
end