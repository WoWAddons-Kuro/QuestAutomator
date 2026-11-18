-- QuestAutomator: the page under Esc > Options > AddOns > Quest Automator. A canvas
-- layout (Settings.RegisterCanvasLayoutCategory, InterfaceOptions_AddCategory on
-- older clients) in the GotJunk style: a scrolling content frame, a title and
-- intro, bordered sections with a header, and plain checkbox / radio / slider
-- widgets in one left-aligned column. Every widget carries an Update() that reads
-- NS.db.settings, so slash commands and the page never disagree; the whole tree is
-- refreshed OnShow.
local ADDON, NS = ...
local L = NS.L

local optionsCategory, optionsFrame

local BOX_W, PAD = 580, 10

local function Changed()
	NS.OnSettingsChanged()
	if optionsFrame and optionsFrame.Update and optionsFrame:IsShown() then optionsFrame:Update() end
end

--------------------------------------------------------------------------------
-- Widgets. Each returns a frame with :Update() reading the live setting.
--------------------------------------------------------------------------------
local function Check(parent, key, label, tip, onChange)
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	cb.Text:SetText(label)
	cb.tooltipText = tip
	cb:SetScript("OnClick", function(self)
		NS.db.settings[key] = self:GetChecked() and true or false
		if onChange then onChange(NS.db.settings[key]) end
		Changed()
	end)
	cb.Update = function(self) self:SetChecked(NS.db.settings[key] and true or false) end
	return cb
end

-- A horizontal radio group on one row: label on the left, one radio per value.
-- A radio group. Inline (default): label on the left, radios to its right on the same
-- line (label column labelWidth wide). wrap = true: radios on a second line, indented.
local function RadioRow(parent, key, label, values, names, tip, opts)
	opts = opts or {}
	local wrap = opts.wrap
	local labelWidth = opts.labelWidth or 300
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(BOX_W - 2 * PAD, wrap and 40 or 20)
	local text = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	if wrap then
		text:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -2)
		text:SetWidth(BOX_W - 2 * PAD - 8)
	else
		text:SetPoint("LEFT", holder, "LEFT", 4, 0)
		text:SetWidth(labelWidth)
	end
	text:SetJustifyH("LEFT")
	text:SetText(label)
	holder.radios = {}
	local anchor
	for i, value in ipairs(values) do
		local r = CreateFrame("CheckButton", nil, holder, "UIRadioButtonTemplate")
		r:SetSize(16, 16)
		if i == 1 then
			if wrap then r:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 20, -6) else r:SetPoint("LEFT", text, "RIGHT", 8, 0) end
		else
			r:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
		end
		r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		r.text:SetPoint("LEFT", r, "RIGHT", 3, 0)
		r.text:SetText(names[value] or tostring(value))
		r.value = value
		r:SetScript("OnClick", function()
			NS.db.settings[key] = value
			for _, o in ipairs(holder.radios) do o:SetChecked(o.value == value) end
			Changed()
		end)
		if tip then
			r:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label, 1, 1, 1); GameTooltip:AddLine(tip, nil, nil, nil, true); GameTooltip:Show() end)
			r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		holder.radios[#holder.radios + 1] = r
		anchor = r.text
	end
	holder.Update = function(self)
		for _, o in ipairs(self.radios) do o:SetChecked(NS.db.settings[key] == o.value) end
	end
	return holder
end

-- Slider with its label above-left so it lines up with the checkboxes.
local function Slider(parent, name, key, minV, maxV, labelFn)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(BOX_W - 2 * PAD, 44)
	local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 4, 0)
	local s = CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 2, -6)
	s:SetWidth(220)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(1)
	s:SetObeyStepOnDrag(true)
	_G[name .. "Low"]:SetText(tostring(minV))
	_G[name .. "High"]:SetText(tostring(maxV))
	_G[name .. "Text"]:SetText("")
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v + 0.5)
		if NS.db.settings[key] ~= v then
			NS.db.settings[key] = v
			NS.OnSettingsChanged()
		end
		label:SetText(labelFn(v))
	end)
	holder.Update = function()
		local v = tonumber(NS.db.settings[key]) or minV
		s:SetValue(v)
		label:SetText(labelFn(v))
	end
	return holder
end

-- Plain text line (read-only facts).
local function Note(parent, width)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetWidth(width or (BOX_W - 2 * PAD - 8))
	fs:SetJustifyH("LEFT")
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(BOX_W - 2 * PAD, 14)
	fs:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, 0)
	holder.text = fs
	return holder
end

--------------------------------------------------------------------------------
-- The page.
--------------------------------------------------------------------------------
local function Build()
	optionsFrame = CreateFrame("Frame", "QuestAutomatorOptions")
	optionsFrame.name = L["Quest Automator"]

	local scroll = CreateFrame("ScrollFrame", "QuestAutomatorOptionsScroll", optionsFrame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(620, 1400)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(math.max(620, w)) end)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = self:GetVerticalScrollRange()
		self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
	end)

	local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L["Quest Automator"] .. "  |cff808080" .. tostring(NS.version) .. "|r")
	local sub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetWidth(560)
	sub:SetJustifyH("LEFT")
	sub:SetText(L["Accepts and hands in quests for you and picks the reward. Rewards go through the tiers below, first match wins; each tier either picks automatically or only recommends (the suggested reward glows and the window stays open). Hold the pause key while talking to an NPC to do that conversation by hand."])

	local last, lastDy = sub, -14
	local function Place(w, dy) w:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, dy or lastDy); last = w; lastDy = -6 end

	local function Section(header)
		local box = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
		box:SetWidth(BOX_W)
		if box.SetBackdrop then
			box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			box:SetBackdropColor(0, 0, 0, 0.25)
			box:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.6)
		end
		local h = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		h:SetPoint("TOPLEFT", PAD, -PAD)
		h:SetText(header)
		box.inner_last, box.inner_h = h, PAD + 14
		function box:Add(w, height, dy, dx)
			dy = dy or -6
			w:SetPoint("TOPLEFT", self.inner_last, "BOTTOMLEFT", dx or 0, dy)
			self.inner_last, self.inner_h = w, self.inner_h - dy + height
			return w
		end
		function box:Finish() self:SetHeight(self.inner_h + PAD) end
		Place(box, -14)
		return box
	end

	-- Master switch directly under the intro.
	Place(Check(content, "enabled", L["Enable the automation"], L["Master switch. Holding the pause key while talking to an NPC pauses everything for that conversation."]), -14)

	-- Section: Quests
	local q = Section(L["Quests"])
	q:Add(Check(q, "accept", L["Accept quests"], L["Take every quest an NPC offers, except the kinds excluded below."]), 26)
	q:Add(Check(q, "acceptTrivial", L["Also accept low-level quests"], L["Low-level (grey) quests are skipped unless this is on."]), 26, -2, 20)
	q:Add(Check(q, "acceptRepeatable", L["Also accept daily and repeatable quests"], L["Daily, weekly and repeatable quests are skipped unless this is on."]), 26, -2)
	q:Add(Check(q, "confirmPartyQuests", L["Accept escorts started by the party"], L["Answer the confirmation pop-up that appears when a party member starts an escort quest."]), 26, -2)
	q:Add(Check(q, "turnIn", L["Hand in quests"], L["Hand in every completed quest and take its reward as configured below. Quests that cost money are always left to you."]), 26, -8, -20)
	q:Add(Check(q, "turnInRepeatable", L["Also hand in daily and repeatable quests"], L["Repeatable quests usually consume items from your bags; they are left to you unless this is on."]), 26, -2, 20)
	q:Finish()

	-- Section: Reward tiers
	local actionNames = NS.TierActionNames()
	local shortNames = { auto = L["auto"], recommend = L["recommend"] }
	local t = Section(L["Reward tiers (first match wins)"])
	local tierRows = {
		{ "1", L["Hard to value (trinket, relic, Use or proc effect, not equipment)"], L["When any reward is a trinket, a relic, has a Use or chance-on-hit effect, or is not equipment at all. Recommend is the safe choice: the addon cannot weigh these."] },
		{ "2", L["One reward is a clear upgrade"], L["Exactly one wearable reward has a higher item level than what you wear in that slot (by more than the sidegrade band)."] },
		{ "3", L["One reward is a sidegrade"], L["Exactly one wearable reward is within the sidegrade band of what you wear in that slot."] },
		{ "4", L["Two or more rewards are upgrades or sidegrades"], L["Several wearable rewards would improve or match your gear. Recommend lets you weigh them; the glow marks the one with the biggest item-level gain."] },
		{ "5", L["Nothing wearable: most valuable"], L["No reward fits your class's best armour class or weapon skills: take the one worth the most."] },
	}
	for i, row in ipairs(tierRows) do
		t:Add(RadioRow(t, NS.Engine.TIER_SETTING[row[1]], row[1] .. ". " .. row[2], NS.TIER_ACTIONS, shortNames, row[3], { labelWidth = 360 }), 20, i == 1 and -8 or -4)
	end
	local qualityNames = {}
	for _, v in ipairs(NS.QUALITY_CHOICES) do qualityNames[v] = NS.QualityName(v) end
	t:Add(RadioRow(t, "manualQuality", L["Leave the choice to me from quality"], NS.QUALITY_CHOICES, qualityNames, L["When any reward is of this quality or better, the reward window stays open for you to choose."], { wrap = true }), 40, -10)
	t:Add(Slider(t, "QuestAutomatorOptionsBand", "ilvlBand", 0, 10, function(v) return string.format(L["Sidegrade band: %d item levels either side of what you wear"], v) end), 44, -10)
	t:Finish()

	-- Section: What counts as wearable / valuable
	local w = Section(L["Wearable and valuable"])
	w:Add(RadioRow(w, "weaponProficiency", L["Wearable weapons"], NS.WEAPON_PROFICIENCIES,
		{ learnable = L["weapons my class can learn"], usable = L["weapons I have trained"] },
		L["Which weapons count as wearable: every weapon your class can train at some trainer, or only those you have the skill for right now."], { labelWidth = 160 }), 20, -8)
	w:Add(RadioRow(w, "valueSource", L["Most valuable means"], NS.VALUE_SOURCES,
		{ vendor = L["vendor price"], auction = L["auction value"], disenchant = L["disenchant value"] },
		L["How the value of a reward is measured. Auction and disenchant values need a provider addon; without one the vendor price is used."], { labelWidth = 160 }), 20, -4)
	local weights = w:Add(Note(w), 28, -10)
	weights.Update = function(self)
		local player = NS.Rules.Player()
		local ordered = {}
		for key, weight in pairs(player.weights) do ordered[#ordered + 1] = { key = key, weight = weight } end
		table.sort(ordered, function(a, b) if a.weight ~= b.weight then return a.weight > b.weight end return a.key < b.key end)
		local bits = {}
		for i = 1, math.min(8, #ordered) do bits[#bits + 1] = string.format("%s %.2f", NS.Rules.StatName(ordered[i].key), ordered[i].weight) end
		self.text:SetText(string.format(L["Tie-break stat weights for %s: %s"], tostring(player.class), table.concat(bits, ", ")))
	end
	w:Finish()

	-- Section: Pre-pick and feedback
	local p = Section(L["Pre-pick and feedback"])
	p:Add(Check(p, "prePickUI", L["Ask me when I accept a quest"], L["When a quest you accept has a reward the addon would only recommend, show the choices right away so the hand-in can still be automatic."]), 26)
	p:Add(Check(p, "announce", L["Announcements"], L["Print a chat line for every quest accepted, handed in and reward chosen."]), 26, -2)
	p:Add(Check(p, "xpBar", L["Completed quests on the experience bar"]), 26, -2)
	p:Add(Check(p, "minimap", L["Minimap button"], L["Show the button on the minimap. Left-click switches the automation on or off, right-click opens the menu, drag moves it."],
		function(value) if NS.ShowMinimapButton then NS.ShowMinimapButton(value) end end), 26, -2)
	p:Add(RadioRow(p, "modifier", L["Pause key"], NS.MODIFIERS, { SHIFT = "Shift", CTRL = "Ctrl", ALT = "Alt", NONE = L["none"] },
		L["Hold this key while talking to an NPC to do that conversation by hand."], { labelWidth = 160 }), 20, -8)
	p:Finish()

	local function LayoutContentHeight()
		local top, bottom = content:GetTop(), p:GetBottom()
		if top and bottom then content:SetHeight(top - bottom + 24) end
	end
	local function UpdateTree(frame)
		for _, child in ipairs({ frame:GetChildren() }) do
			if child.Update then child:Update() end
			UpdateTree(child)
		end
	end
	optionsFrame.Update = function(self)
		UpdateTree(content)
		LayoutContentHeight()
	end
	optionsFrame:SetScript("OnShow", optionsFrame.Update)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsFrame, L["Quest Automator"])
		Settings.RegisterAddOnCategory(optionsCategory)
		NS.features["Settings.RegisterCanvasLayoutCategory"] = true
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(optionsFrame)
		NS.features["InterfaceOptions_AddCategory"] = true
	else
		return nil
	end
	return optionsCategory or optionsFrame
end

function NS.RegisterSettings()
	if NS.settingsCategory then return true end
	if not NS.db then return false end
	local ok, result = pcall(Build)
	if not ok then
		NS.WarnOnce("settings", result)
		return false
	end
	if not result then return false end
	NS.settingsCategory = result
	return true
end

function NS.OpenSettings()
	if not NS.RegisterSettings() then
		NS.Print(L["The settings page is not available on this client; use the /qam commands."])
		return false
	end
	if Settings and Settings.OpenToCategory and optionsCategory then
		local ok, err = pcall(Settings.OpenToCategory, optionsCategory:GetID())
		if not ok then NS.WarnOnce("settings-open", err) return false end
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(optionsFrame)
		InterfaceOptionsFrame_OpenToCategory(optionsFrame)
	end
	return true
end

NS.RegisterEvent("PLAYER_LOGIN", function()
	NS.RegisterSettings()
end)