-- Quest Automator: the stat-weight editor (SPECS/STAT_PROFILES.md). The grid shows
-- the character's SELECTED stat profile: name, an edit box with the profile's weight,
-- and - on a custom profile - the forked-from built-in's value greyed behind it.
--
-- Editing a cell of a BUILT-IN profile forks it: a "Custom: <name>" copy is created
-- with the edit applied and this character is switched to it; the built-in is never
-- touched. Editing a custom profile edits it in place (every character on that
-- profile sees the change - it is one shared row). Custom profiles are account-wide;
-- the selection is per character.
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

-- The profile the grid edits. Writing to a built-in forks it first (owner rule) and
-- moves this character onto the fork. Returns the profile written to, or nil.
local function EditableProfile(class)
	local p = Rules.SelectedProfile(class)
	if not p then return nil end
	if p.builtin then
		local fork = Rules.ForkProfile(p.id)
		if not fork then return nil end
		Rules.SelectProfile(fork.id)
		return fork
	end
	return p
end
StatWeights.EditableProfile = EditableProfile

-- Set one weight on the selected profile (forking a built-in). nil clears the cell
-- back to the base value - on a custom profile that is the forked-from built-in's.
local function WriteWeight(class, key, value)
	local p = EditableProfile(class)
	if not p then return false end
	if value == nil then value = Rules.ProfileBaseWeight(p.id, key) end
	-- a cell back at its base value stays explicit in the row: the row is COMPLETE, by design
	return Rules.SetProfileWeight(p.id, key, value)
end
StatWeights.WriteWeight = WriteWeight

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
	-- Placeholder: the class default, grey, inside the box while it is empty.
	row.Placeholder = row.Box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Placeholder:SetPoint("RIGHT", row.Box, "RIGHT", -2, 0)
	row.Placeholder:SetJustifyH("RIGHT")
	local function RefreshPlaceholder()
		local text = row.Box:GetText() or ""
		row.Placeholder:SetShown(text == "" and (row.Placeholder:GetText() or "") ~= "")
	end
	local function Commit(box)
		local class = Rules.Class()
		if not class then return end
		local text = box:GetText() or ""
		if text:match("^%s*$") then
			WriteWeight(class, entry.key, nil) -- cleared: back to the base value
			row:Update()
			if onChanged then onChanged() end
			return
		end
		local v = ParseWeight(text)
		if v == nil then
			row:Update()
			return
		end
		WriteWeight(class, entry.key, v)
		row:Update()
		if onChanged then onChanged() end
	end
	row.Box:SetScript("OnEnterPressed", function(self) Commit(self); self:ClearFocus() end)
	row.Box:SetScript("OnEditFocusLost", Commit)
	row.Box:SetScript("OnEscapePressed", function(self) row:Update(); self:ClearFocus() end)
	row.Box:SetScript("OnTextChanged", RefreshPlaceholder)
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
		local p = Rules.SelectedProfile(class)
		local value = p and p.weights[entry.key] or 0
		local base = p and Rules.ProfileBaseWeight(p.id, entry.key) or 0
		-- Built-in: the value sits in the box as-is, nothing greyed. Custom: a cell that
		-- differs from the forked-from built-in shows its value in the box and the base
		-- greyed behind it; a cell equal to the base shows the base greyed only.
		local changed = p and not p.builtin and value ~= base
		self.Placeholder:SetText(base > 0 and FormatWeight(base) or "")
		if p and (p.builtin or changed) then
			self.Box:SetText(value > 0 and FormatWeight(value) or (changed and "0" or ""))
			self.Label:SetTextColor(1, 0.82, 0)
			if not changed then self.Label:SetTextColor(1, 1, 1) end
			if value > 0 then self.Box:SetTextColor(1, 1, 1) else self.Box:SetTextColor(0.5, 0.5, 0.5) end
		else
			self.Box:SetText("")
			self.Label:SetTextColor(1, 1, 1)
		end
		RefreshPlaceholder()
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
	holder.Reset:SetText(L["Reset this profile"])
	holder.Reset:SetScript("OnClick", function()
		local p = Rules.SelectedProfile(Rules.Class())
		if p and not p.builtin then Rules.ResetProfile(p.id) end
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
		local p = Rules.SelectedProfile(class)
		self.Intro:SetText(string.format(L["Stat values for your %s - profile: %s. One point of each stat is worth this much; a reward's value is the sum, compared with what you wear in the same slot. Editing a built-in profile makes a custom copy; changed values are shown in gold."], localized, p and p.name or "?"))
		-- Reset only means something on a custom profile (back to its built-in).
		if self.Reset.SetEnabled then self.Reset:SetEnabled(p ~= nil and not p.builtin) end
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
