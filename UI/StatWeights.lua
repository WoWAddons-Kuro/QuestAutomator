-- Quest Automator: the stat-weight editor. One column of stats for the CURRENT
-- class: name, an edit box with the effective weight, and the class default in
-- grey when the player has changed it. Values are stored per class, account wide
-- (NS.db.statWeights[class][key], Rules.SetUserWeight); only the class being
-- played is shown, the others keep their defaults until that character edits them.
--
-- Returns a widget that fits the Settings.lua section API (Layout(width) -> height,
-- Update()), so Settings.lua only adds it to a section.
local ADDON, NS = ...
local L = NS.L
local Rules = NS.Rules
local StatWeights = {}
NS.StatWeights = StatWeights

StatWeights.ROW_HEIGHT = 20
StatWeights.COLS = 2        -- stats laid out in this many columns
StatWeights.BOX_WIDTH = 46  -- the edit box

local function ParseWeight(text)
	local v = tonumber((tostring(text or ""):gsub(",", ".")))
	if not v or v < 0 then return nil end
	if v > 99 then v = 99 end
	return math.floor(v * 100 + 0.5) / 100
end

local function FormatWeight(v)
	if v == nil then return "" end
	if v == math.floor(v) then return tostring(v) end
	return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end

-- One stat row: label | [edit] | default-in-grey
local function BuildRow(parent, entry, onChanged)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(StatWeights.ROW_HEIGHT)
	row.key = entry.key
	row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Label:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.Label:SetJustifyH("LEFT")
	row.Label:SetWordWrap(false)
	row.Label:SetText(Rules.StatName(entry.key))
	row.Box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.Box:SetSize(StatWeights.BOX_WIDTH, 18)
	row.Box:SetAutoFocus(false)
	row.Box:SetNumeric(false)
	row.Box:SetMaxLetters(5)
	row.Box:SetJustifyH("RIGHT")
	row.Default = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Default:SetPoint("LEFT", row.Box, "RIGHT", 4, 0)
	row.Default:SetJustifyH("LEFT")
	local function Commit(box)
		local class = Rules.Class()
		if not class then return end
		local v = ParseWeight(box:GetText())
		if v == nil then
			row:Update()
			return
		end
		Rules.SetUserWeight(class, entry.key, v)
		row:Update()
		if onChanged then onChanged() end
	end
	row.Box:SetScript("OnEnterPressed", function(self) Commit(self); self:ClearFocus() end)
	row.Box:SetScript("OnEditFocusLost", Commit)
	row.Box:SetScript("OnEscapePressed", function(self) row:Update(); self:ClearFocus() end)
	row.Box:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(Rules.StatName(entry.key), 1, 1, 1)
		GameTooltip:AddLine(L["How much one point of this stat is worth to your class. 0 = ignored. Clear the box or enter the default to go back to it."], nil, nil, nil, true)
		GameTooltip:Show()
	end)
	row.Box:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	function row:Update()
		local class = Rules.Class()
		local effective = Rules.EffectiveWeight(class, entry.key)
		local default = Rules.DefaultWeight(class, entry.key)
		self.Box:SetText(FormatWeight(effective))
		if Rules.UserWeight(class, entry.key) ~= nil then
			self.Default:SetText(string.format(L["default %s"], FormatWeight(default)))
			self.Label:SetTextColor(1, 0.82, 0)
		else
			self.Default:SetText("")
			self.Label:SetTextColor(1, 1, 1)
		end
		if effective > 0 then self.Box:SetTextColor(1, 1, 1) else self.Box:SetTextColor(0.5, 0.5, 0.5) end
	end
	return row
end

-- The widget Settings.lua embeds. onChanged runs after any edit (refresh the page).
function StatWeights.Build(parent, onChanged)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetHeight(1)
	holder.Intro = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	holder.Intro:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, 0)
	holder.Intro:SetJustifyH("LEFT")
	holder.Intro:SetWordWrap(true)
	holder.Reset = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
	holder.Reset:SetSize(140, 22)
	holder.Reset:SetText(L["Reset to class defaults"])
	holder.Reset:SetScript("OnClick", function()
		local class = Rules.Class()
		if class then Rules.ResetUserWeights(class) end
		holder:Update()
		if onChanged then onChanged() end
	end)
	holder.statRows = {} -- not "rows": Settings' layout checker treats .rows as Stack entries
	for _, entry in ipairs(Rules.EDITABLE_STATS) do
		holder.statRows[#holder.statRows + 1] = BuildRow(holder, entry, onChanged)
	end
	function holder:Update()
		local class = Rules.Class() or "?"
		local localized = NS.SafeString(select(1, NS.Call("UnitClass", "player"))) or class
		self.Intro:SetText(string.format(L["Stat values for your %s. One point of each stat is worth this much; a reward's value is the sum, compared with what you wear in the same slot. Changed values are shown in gold."], localized))
		for _, row in ipairs(self.statRows) do row:Update() end
	end
	function holder:Layout(availableWidth)
		self:SetWidth(availableWidth)
		self.Intro:SetWidth(math.max(1, availableWidth - 8))
		local y = self.Intro:GetStringHeight() + 10
		local cols = StatWeights.COLS
		local colW = math.floor((availableWidth - 8) / cols)
		local labelW = math.max(40, colW - StatWeights.BOX_WIDTH - 60)
		for i, row in ipairs(self.statRows) do
			local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", self, "TOPLEFT", 4 + col * colW, -(y + line * StatWeights.ROW_HEIGHT))
			row:SetWidth(colW - 6)
			row.Label:SetWidth(labelW)
			row.Box:ClearAllPoints()
			row.Box:SetPoint("LEFT", row, "LEFT", labelW + 8, 0)
		end
		local lines = math.ceil(#self.statRows / cols)
		y = y + lines * StatWeights.ROW_HEIGHT + 8
		self.Reset:ClearAllPoints()
		self.Reset:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -y)
		y = y + 22 + 4
		self:SetHeight(y)
		return y
	end
	return holder
end
