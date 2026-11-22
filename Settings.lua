-- QuestAutomator: the page under Esc > Options > AddOns > Quest Automator. A canvas
-- layout (Settings.RegisterCanvasLayoutCategory, InterfaceOptions_AddCategory on
-- older clients) in the GotJunk style: a scrolling content frame, a title and
-- intro, bordered sections with a header, and plain checkbox / radio / slider
-- widgets in one left-aligned column. Every widget carries an Update() that reads
-- NS.db.settings, so slash commands and the page never disagree; the whole tree is
-- refreshed OnShow.
local ADDON, NS = ...
local L = NS.L
local Layout = NS.SettingsLayout

local optionsCategory, optionsFrame

local BOX_W, PAD = 580, 10

local function Changed()
	NS.OnSettingsChanged()
	if optionsFrame and optionsFrame.Update and optionsFrame:IsShown() then optionsFrame:Update() end
end

-- Other modules (the pick window's close box) change a setting behind the page's back.
function NS.RefreshSettingsPage()
	if optionsFrame and optionsFrame.Update and optionsFrame:IsShown() then optionsFrame:Update() end
end

--------------------------------------------------------------------------------
-- Widgets. Each returns a frame with :Update() reading the live setting.
--------------------------------------------------------------------------------
local function Check(parent, key, label, tip, onChange)
	local holder = CreateFrame("Frame", nil, parent)
	local cb = CreateFrame("CheckButton", nil, holder, "InterfaceOptionsCheckButtonTemplate")
	cb:SetSize(26, 26)
	cb:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	cb.Text:ClearAllPoints()
	cb.Text:SetPoint("TOPLEFT", holder, "TOPLEFT", 30, -6)
	cb.Text:SetJustifyH("LEFT")
	cb.Text:SetWordWrap(true)
	cb.Text:SetText(label)
	cb.tooltipText = tip
	cb:SetScript("OnClick", function(self)
		NS.db.settings[key] = self:GetChecked() and true or false
		if onChange then onChange(NS.db.settings[key]) end
		Changed()
	end)
	cb.Update = function(self) self:SetChecked(NS.db.settings[key] and true or false) end
	holder.Layout = function(self, availableWidth)
		cb.Text:SetWidth(math.max(1, availableWidth - 30))
		local height = math.max(26, cb.Text:GetStringHeight() + 8)
		cb:SetHitRectInsets(0, -math.max(0, availableWidth - 26), 0, -(height - 26))
		return height
	end
	holder.checkbox, holder.label = cb, cb.Text
	return holder
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
	text:SetWordWrap(true)
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
		r.text:SetWordWrap(true)
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
	holder.label = text
	holder.Layout = function(self, availableWidth)
		local optionWidths, totalWidth = {}, 0
		for i, radio in ipairs(self.radios) do
			radio.text:SetWidth(0)
			optionWidths[i] = 19 + math.ceil(radio.text:GetStringWidth())
			totalWidth = totalWidth + optionWidths[i] + (i > 1 and 14 or 0)
		end
		text:ClearAllPoints()
		text:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -2)
		text:SetWidth(math.max(1, math.min(labelWidth, availableWidth - 8)))
		local stacked = wrap or totalWidth > availableWidth - labelWidth - 12 or text:GetStringHeight() > 20
		local optionsX, optionsY = labelWidth + 12, 2
		if stacked then
			text:SetWidth(math.max(1, availableWidth - 8))
			optionsX, optionsY = 24, 2 + text:GetStringHeight() + 8
		end
		local plan = Layout.Flow(math.max(1, availableWidth - optionsX - 4), optionWidths, function(i, cellWidth)
			local label = self.radios[i].text
			label:SetWidth(math.max(1, cellWidth - 19))
			return label:GetStringHeight() + 2
		end)
		for i, cell in ipairs(plan.cells) do
			local radio = self.radios[i]
			radio:ClearAllPoints()
			radio:SetPoint("TOPLEFT", self, "TOPLEFT", optionsX + cell.x, -(optionsY + cell.y))
			radio.text:ClearAllPoints()
			radio.text:SetPoint("TOPLEFT", radio, "TOPRIGHT", 3, -1)
			radio:SetHitRectInsets(0, -(cell.width - 16), 0, -(cell.height - 16))
		end
		self.optionLayout, self.optionsX, self.optionsY = plan, optionsX, optionsY
		return math.max(20, optionsY + plan.height + 4)
	end
	return holder
end

-- Slider with its label above-left so it lines up with the checkboxes.
local function Slider(parent, name, key, minV, maxV, labelFn)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(BOX_W - 2 * PAD, 44)
	local label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 4, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(true)
	local s = CreateFrame("Slider", name, holder, "OptionsSliderTemplate")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(1)
	s:SetObeyStepOnDrag(true)
	_G[name .. "Low"]:SetText(tostring(minV))
	_G[name .. "High"]:SetText(tostring(maxV))
	_G[name .. "Text"]:SetText("")
	s:SetScript("OnValueChanged", function(self, v)
		if self.updatingValue then return end
		v = math.floor(v + 0.5)
		if NS.db.settings[key] ~= v then
			NS.db.settings[key] = v
			Changed()
		end
		label:SetText(labelFn(v))
	end)
	holder.Update = function()
		local v = tonumber(NS.db.settings[key]) or minV
		s.updatingValue = true
		s:SetValue(v)
		s.updatingValue = false
		label:SetText(labelFn(v))
	end
	holder.Layout = function(self, availableWidth)
		label:SetWidth(math.max(1, availableWidth - 8))
		s:ClearAllPoints()
		s:SetPoint("TOPLEFT", self, "TOPLEFT", 6, -(label:GetStringHeight() + 10))
		s:SetWidth(math.max(1, math.min(220, availableWidth - 12)))
		return label:GetStringHeight() + 10 + 20 + 18
	end
	holder.label, holder.slider = label, s
	return holder
end

-- Plain text line (read-only facts).
local function Note(parent, width)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetWidth(width or (BOX_W - 2 * PAD - 8))
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(BOX_W - 2 * PAD, 14)
	fs:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, 0)
	holder.text = fs
	holder.Layout = function(self, availableWidth)
		fs:SetWidth(math.max(1, math.min(width or availableWidth, availableWidth - 8)))
		return fs:GetStringHeight() + 2
	end
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
	content:SetSize(620, 1)
	scroll:SetScrollChild(content)
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
	sub:SetText(L["Automatically accepts and turns in quests. Pre-pick rewards or use automatic selection. Settings marked Not implemented do not affect automation."])

	local pageRows = {}
	local function Place(w, dy)
		pageRows[#pageRows + 1] = {widget = w, gap = -(dy or -6), indent = 0}
	end

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
		h:SetJustifyH("LEFT")
		h:SetWordWrap(true)
		box.rows, box.indent = {}, 0
		function box:Add(w, height, dy, dx)
			self.indent = self.indent + (dx or 0)
			self.rows[#self.rows + 1] = {widget = w, minHeight = height, gap = -(dy or -6), indent = self.indent}
			return w
		end
		function box:Layout(width)
			self:SetWidth(width)
			h:SetWidth(math.max(1, width - 2 * PAD))
			local bottom = Layout.Stack(self.rows, math.max(1, width - 2 * PAD), PAD + h:GetStringHeight())
			for _, entry in ipairs(self.rows) do
				entry.widget:ClearAllPoints()
				entry.widget:SetPoint("TOPLEFT", self, "TOPLEFT", PAD + entry.x, -entry.y)
			end
			self:SetHeight(bottom + PAD)
			return self:GetHeight()
		end
		function box:Finish() self:Layout(BOX_W) end
		Place(box, -14)
		return box
	end

	-- Master switch directly under the intro.
	Place(Check(content, "enabled", L["Enable the automation"], L["Master switch. Holding the pause key while talking to an NPC pauses everything for that conversation."]), -14)
	local pauseNote = Note(content)
	pauseNote.text:SetText(L["Note: ANY modifier key (Shift, Ctrl or Alt) held while talking to an NPC stops the auto-interact for that conversation."])
	Place(pauseNote, -2)
	Place(Check(content, "minimap", L["Minimap button"], L["Left-click: toggle the pick window. Right-click: settings. Drag to move."],
		function(value) if NS.ShowMinimapButton then NS.ShowMinimapButton(value) end end), -2)

	-- Section: Quest dialog automation
	local q = Section(L["Quest Dialog Automation"])
	q:Add(Check(q, "accept", L["Accept quests"], L["Take every quest an NPC offers, except the kinds excluded below."]), 26)
	q:Add(Check(q, "acceptTrivial", L["Also accept low-level quests"], L["Low-level (grey) quests are skipped unless this is on."]), 26, -2, 20)
	q:Add(Check(q, "acceptRepeatable", L["Also accept daily and repeatable quests"], L["Daily, weekly and repeatable quests are skipped unless this is on."]), 26, -2)
	q:Add(Check(q, "confirmPartyQuests", L["Accept escorts started by the party"], L["Answer the confirmation pop-up that appears when a party member starts an escort quest."]), 26, -2)
	q:Add(Check(q, "turnIn", L["Hand in quests"], L["Hand in every completed quest and take its reward as configured below. Quests that cost money are always left to you."]), 26, -8, -20)
	q:Add(Check(q, "turnInRepeatable", L["Also hand in daily and repeatable quests"], L["Repeatable quests usually consume items from your bags; they are left to you unless this is on."]), 26, -2, 20)
	q:Finish()

	-- Section: Reward tiers
	-- Original reward settings are functional. Retained tier controls below are state only.
	local r = Section(L["Reward selection"])
	r:Add(RadioRow(r, "rewardMode", L["Reward choice"], NS.REWARD_MODES,
		{ fit = L["Best fit"], value = L["Vendor value"], manual = L["Manual"] },
		L["Best fit compares the armour class you wear at your level and the stats your class wants. Most valuable takes the reward with the highest vendor price."], { labelWidth = 160 }), 20)
	r:Add(Check(r, "fallbackToValue", L["No upgrade: take the most valuable"]), 26)
	local qualityNames = {}
	for _, v in ipairs(NS.QUALITY_CHOICES) do qualityNames[v] = NS.QualityName(v) end
	r:Add(RadioRow(r, "manualQuality", L["Leave the choice to me from quality"], NS.QUALITY_CHOICES, qualityNames, L["When any reward is of this quality or better, the reward window stays open for you to choose."], { wrap = true }), 40, -10)
	r:Finish()

	local ui = NS.UIState
	-- One of three explicit verbs per tier; "auto" was dropped because it meant
	-- "take the upgrade" on some tiers and "take the cash" on others.
	local shortNames = { ask = L["ask me"], upgrade = L["take the upgrade"], cash = L["take the cash"] }
	local t = Section(L["Reward tiers (first match wins)"])
	t:Add(Note(t), 28).text:SetText(L["One upgrade: take it. Two or more upgrades: ask. No upgrade: take the best cash item. Each step's default can be changed below. Ask me = glow the suggestion and leave the window open. Take the upgrade = the biggest stat gain. Take the cash = the highest vendor price, wearable or not."])
	local tierRows = {
		{ "1", L["Ambiguous rewards (trinket, relic, or only consumables)"], L["When a reward is a trinket or relic, or when only consumables such as potions and food are offered. The addon cannot weigh these, so asking you is the safe choice. Weapons are ordinary gear and follow the rules below."] },
		{ "2", L["One reward is a clear upgrade"], L["Exactly one reward adds more stat value than the upgrade margin over what you wear in that slot."] },
		{ "4", L["Two or more rewards are upgrades"], L["Several rewards would improve your gear. Recommend lets you weigh them; the coin marks the one with the biggest gain."] },
		{ "5", L["Nothing is an upgrade: best cash item"], L["No reward beats what you wear, so every reward is vendor trash. Take the one with the highest vendor price - whether or not your class could wear it. (There is no upgrade to take here, so that choice acts as take the cash.)"] },
	}
	for i, row in ipairs(tierRows) do
		t:Add(RadioRow(t, "tier" .. row[1] .. "Action", i .. ". " .. row[2], ui.TIER_ACTIONS, shortNames, row[3], { wrap = true }), 52, -8)
	end
	-- Upgrade threshold: how many percent more stat score than the worn item a reward
	-- needs before it counts as an upgrade at all. Below it = sidegrade = cash.
	t:Add(Slider(t, "QuestAutomatorOptionsBand", "upgradeBand", 0, 50, function(v)
		return L["Upgrade threshold (percent of score)"] .. ": " .. v .. "%  -  " .. L["a reward must score at least this much more than what you wear to count as an upgrade"]
	end), 58, -10)
	t:Finish()

	-- Section: What counts as wearable / valuable
	local w = Section(L["Wearable and valuable"])
	w:Add(Note(w), 36).text:SetText(ui.PlaceholderTip())
	w:Add(RadioRow(w, "weaponProficiency", L["Wearable weapons"], ui.WEAPON_PROFICIENCIES,
		{ learnable = L["weapons my class can learn"], usable = L["weapons I have trained"] },
		L["Which weapons count as wearable: every weapon your class can train at some trainer, or only those you have the skill for right now."], { wrap = true }), 40, -8)
	w:Add(RadioRow(w, "valueSource", ui.PlaceholderLabel(L["Most valuable means"]), ui.VALUE_SOURCES,
		{ vendor = L["vendor price"], auction = L["auction value"], disenchant = L["disenchant value"] },
		ui.PlaceholderTip(), { wrap = true }), 40, -8)
	w:Finish()

	-- Section: Stat values for the current class (UI/StatWeights.lua)
	if NS.StatWeights then
		local sw = Section(L["Stat values"])
		-- the profile radio group sits above the grid: pick which row the grid edits
		sw:Add(NS.StatWeights.BuildProfileSelector(sw, Changed), 40)
		sw:Add(NS.StatWeights.Build(sw, Changed), 40)
		sw:Finish()
	end

	-- Section: Pre-pick and feedback
	local p = Section(L["Pre-pick and feedback"])
	p:Add(Note(p), 28).text:SetText(L["Pre-select your reward."])
	p:Add(Check(p, "prePickUI", L["Ask me when I accept a quest"], L["Show reward choices on accept. A saved selection is used at hand-in when automation is allowed; turning off this display does not clear saved picks."]), 26)
	p:Add(Check(p, "prePickUnlocked", L["Unlock and show the pick window (drag it, then untick)"], L["Shows the pick window with sample rewards so you can drag it where you want it. The position is remembered; untick to lock it again."],
		function(value) if NS.PrePick and NS.PrePick.SetUnlocked then NS.PrePick.SetUnlocked(value) end end), 26, -2, 20)
	p:Add(Check(p, "announce", L["Chat messages for quests accepted, handed in and rewards chosen"], L["Print a chat line for every quest accepted, handed in and reward chosen."]), 26, -8, -20)
	p:Add(Check(p, "xpBar", L["Completed quests on the experience bar"]), 26, -2)
	p:Add(Check(p, "tooltipScore", L["Score line on equipment tooltips"], L["Adds a Quest Automator line to every equipment tooltip: the item's stat value for your class, the gain or loss against what you wear in that slot, and whether it counts as an upgrade."]), 26, -2)
	p:Add(Check(p, "ahScore", L["Show upgrade scores on auction upgrades"], L["Equipment in the auction house browse list that beats what you wear gets a green +gain bubble at the right of its name (stat points, same scale as the tooltip line). Nothing is shown for sidegrades or downgrades."]), 26, -2)
	p:Add(Check(p, "profileSwitchers", L["Stat profile selector in the auction house and reward panels"], L["Shows which stat profile this character scores with, and lets you switch it, in the pick window and left of the auction house search box. Turn it off if you only ever play one spec; the selector on this page stays."]), 26, -2)
	p:Finish()

	local layingOut = false
	local function LayoutPage()
		if layingOut then return end
		layingOut = true
		local viewportWidth = scroll:GetWidth()
		if not viewportWidth or viewportWidth <= 0 then viewportWidth = 620 end
		content:SetWidth(viewportWidth)
		local sectionWidth = math.min(BOX_W, math.max(1, viewportWidth - 32))
		title:SetWidth(sectionWidth)
		sub:SetWidth(sectionWidth)
		local headerBottom = 16 + title:GetStringHeight() + 6 + sub:GetStringHeight()
		local pageBottom = Layout.Stack(pageRows, sectionWidth, headerBottom)
		for _, entry in ipairs(pageRows) do
			entry.widget:ClearAllPoints()
			entry.widget:SetPoint("TOPLEFT", content, "TOPLEFT", 16 + entry.x, -entry.y)
		end
		content:SetHeight(pageBottom + 24)
		scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange())))
		layingOut = false
	end
	local function UpdateTree(frame)
		for _, child in ipairs({ frame:GetChildren() }) do
			if child.Update then child:Update() end
			UpdateTree(child)
		end
	end
	optionsFrame.Layout = LayoutPage
	optionsFrame.Update = function(self)
		UpdateTree(content)
		LayoutPage()
	end
	optionsFrame:SetScript("OnShow", optionsFrame.Update)
	scroll:SetScript("OnSizeChanged", LayoutPage)
	optionsFrame.layoutRows, optionsFrame.content, optionsFrame.scroll = pageRows, content, scroll
	optionsFrame:Update()

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