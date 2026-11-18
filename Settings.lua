-- QuestAutomator: the page under Options > AddOns, built with the retail
-- Settings API (Blizzard_Settings_Shared\Blizzard_Settings.lua). Every control is
-- a proxy setting reading and writing NS.db.settings, so the slash commands and
-- the page stay in sync. Dropdowns carry numeric values (the index into the
-- option list) as Blizzard's own PROXY_CHAT_BUBBLES example does.
local ADDON, NS = ...
local L = NS.L

local function HasSettingsAPI()
	return Settings ~= nil
		and Settings.RegisterVerticalLayoutCategory ~= nil
		and Settings.RegisterProxySetting ~= nil
		and Settings.CreateCheckbox ~= nil
		and Settings.CreateDropdown ~= nil
		and Settings.CreateControlTextContainer ~= nil
		and Settings.RegisterAddOnCategory ~= nil
		and Settings.VarType ~= nil
end

local function Checkbox(category, variable, key, name, tooltip, onChange)
	local function Get()
		return NS.db.settings[key] and true or false
	end
	local function Set(value)
		NS.db.settings[key] = value and true or false
		if onChange then onChange(NS.db.settings[key]) end
		NS.OnSettingsChanged()
	end
	local default = NS.DEFAULT_SETTINGS[key] and true or false
	local setting = Settings.RegisterProxySetting(category, variable, Settings.VarType.Boolean, name, default, Get, Set)
	Settings.CreateCheckbox(category, setting, tooltip)
	return setting
end

-- `list` holds the stored values, `label(value)` the text shown for each.
local function Dropdown(category, variable, key, list, label, name, tooltip)
	local function IndexOf(value)
		for i, v in ipairs(list) do
			if v == value then return i end
		end
		return 1
	end
	local function Get()
		return IndexOf(NS.db.settings[key])
	end
	local function Set(value)
		NS.db.settings[key] = list[tonumber(value) or 1] or list[1]
		NS.OnSettingsChanged()
	end
	local function Options()
		local container = Settings.CreateControlTextContainer()
		for i, v in ipairs(list) do
			container:Add(i, label(v))
		end
		return container:GetData()
	end
	local setting = Settings.RegisterProxySetting(category, variable, Settings.VarType.Number, name, IndexOf(NS.DEFAULT_SETTINGS[key]), Get, Set)
	Settings.CreateDropdown(category, setting, Options, tooltip)
	return setting
end

local function Build()
	local category = Settings.RegisterVerticalLayoutCategory(L["QuestAutomator"])

	Checkbox(category, "QAM_ENABLED", "enabled",
		L["Enable the automation"],
		L["Master switch. Holding the pause key while talking to an NPC pauses everything for that conversation."])
	Checkbox(category, "QAM_ACCEPT", "accept",
		L["Accept quests"],
		L["Take every quest an NPC offers, except the kinds excluded below."])
	Checkbox(category, "QAM_ACCEPT_TRIVIAL", "acceptTrivial",
		L["Also accept low-level quests"],
		L["Low-level (grey) quests are skipped unless this is on."])
	Checkbox(category, "QAM_ACCEPT_REPEATABLE", "acceptRepeatable",
		L["Also accept daily and repeatable quests"],
		L["Daily, weekly and repeatable quests are skipped unless this is on."])
	Checkbox(category, "QAM_TURNIN", "turnIn",
		L["Hand in quests"],
		L["Hand in every completed quest and take its reward as configured below. Quests that cost money are always left to you."])
	Checkbox(category, "QAM_TURNIN_REPEATABLE", "turnInRepeatable",
		L["Also hand in daily and repeatable quests"],
		L["Repeatable quests usually consume items from your bags; they are left to you unless this is on."])
	Checkbox(category, "QAM_PARTY", "confirmPartyQuests",
		L["Accept escorts started by the party"],
		L["Answer the confirmation pop-up that appears when a party member starts an escort quest."])

	-- Reward priority engine (Engine.lua). One dropdown per tier.
	local function ActionName(v) return v == "auto" and L["pick it automatically"] or L["recommend only (glow, window stays open)"] end
	Dropdown(category, "QAM_TIER1", "tier1Action", NS.TIER_ACTIONS, ActionName,
		L["Hard to value (trinket, relic, Use or proc effect, not equipment)"],
		L["When any reward is a trinket, a relic, has a Use or chance-on-hit effect, or is not equipment at all. Recommend is the safe choice: the addon cannot weigh these."])
	Dropdown(category, "QAM_TIER2", "tier2Action", NS.TIER_ACTIONS, ActionName,
		L["One reward is a clear upgrade"],
		L["Exactly one wearable reward has a higher item level than what you wear in that slot (by more than the sidegrade band)."])
	Dropdown(category, "QAM_TIER3", "tier3Action", NS.TIER_ACTIONS, ActionName,
		L["One reward is a sidegrade"],
		L["Exactly one wearable reward is within the sidegrade band of what you wear in that slot."])
	Dropdown(category, "QAM_TIER4", "tier4Action", NS.TIER_ACTIONS, ActionName,
		L["Two or more rewards are upgrades or sidegrades"],
		L["Several wearable rewards would improve or match your gear. Recommend lets you weigh them; the glow marks the one with the biggest item-level gain."])
	Dropdown(category, "QAM_TIER5", "tier5Action", NS.TIER_ACTIONS, ActionName,
		L["Nothing wearable: most valuable"],
		L["No reward fits your class's best armour class or weapon skills: take the one worth the most."])
	Dropdown(category, "QAM_MANUAL_QUALITY", "manualQuality", NS.QUALITY_CHOICES, NS.QualityName,
		L["Leave the choice to me from quality"],
		L["When any reward is of this quality or better, the reward window stays open for you to choose."])
	Dropdown(category, "QAM_ILVL_BAND", "ilvlBand", { 0, 1, 2, 3, 4, 5, 6, 8, 10 }, function(v) return tostring(v) end,
		L["Sidegrade band (item levels)"],
		L["A reward within this many item levels of what you wear counts as a sidegrade; more than this above it is an upgrade."])
	Dropdown(category, "QAM_WEAPON_PROFICIENCY", "weaponProficiency", NS.WEAPON_PROFICIENCIES,
		function(v) return v == "usable" and L["weapons I have trained"] or L["weapons my class can learn"] end,
		L["Wearable weapons"],
		L["Which weapons count as wearable: every weapon your class can train at some trainer, or only those you have the skill for right now."])
	Dropdown(category, "QAM_VALUE_SOURCE", "valueSource", NS.VALUE_SOURCES,
		function(v) return v == "auction" and L["auction value"] or (v == "disenchant" and L["disenchant value"] or L["vendor price"]) end,
		L["Most valuable means"],
		L["How the value of a reward is measured. Auction and disenchant values need a provider addon; without one the vendor price is used."])
	Checkbox(category, "QAM_PREPICK", "prePickUI",
		L["Ask me when I accept a quest"],
		L["When a quest you accept has a reward the addon would only recommend, show the choices right away so the hand-in can still be automatic."])

	-- Read-only: the class stat weights used to break ties inside a tier.
	-- Retail-only layout call; a failure here must not take the whole page down.
	pcall(function()
		local player = NS.Rules.Player()
		local ordered = {}
		for key, weight in pairs(player.weights) do ordered[#ordered + 1] = { key = key, weight = weight } end
		table.sort(ordered, function(a, b) if a.weight ~= b.weight then return a.weight > b.weight end return a.key < b.key end)
		local bits = {}
		for i = 1, math.min(8, #ordered) do bits[#bits + 1] = string.format("%s %.2f", NS.Rules.StatName(ordered[i].key), ordered[i].weight) end
		local text = string.format(L["Tie-break stat weights for %s: %s"], tostring(player.class), table.concat(bits, ", "))
		if Settings.CreateElementInitializer and category.GetLayout then
			local init = Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name = text })
			category:GetLayout():AddInitializer(init)
		end
	end)
	Dropdown(category, "QAM_MODIFIER", "modifier", NS.MODIFIERS,
		function(v) return v == "NONE" and L["none"] or v end,
		L["Pause key"],
		L["Hold this key while talking to an NPC to do that conversation by hand."])
	Checkbox(category, "QAM_ANNOUNCE", "announce",
		L["Announcements"],
		L["Print a chat line for every quest accepted, handed in and reward chosen."])
	Checkbox(category, "QAM_MINIMAP", "minimap",
		L["Minimap button"],
		L["Show the button on the minimap. Left-click switches the automation on or off, right-click opens the menu, drag moves it."],
		function(value) if NS.ShowMinimapButton then NS.ShowMinimapButton(value) end end)

	Settings.RegisterAddOnCategory(category)
	return category
end

function NS.RegisterSettings()
	if NS.settingsCategory then return true end
	if not NS.db then return false end
	NS.features["Settings"] = HasSettingsAPI()
	if not NS.features["Settings"] then return false end
	local ok, result = pcall(Build)
	if not ok then
		NS.WarnOnce("settings", result)
		return false
	end
	NS.settingsCategory = result
	return true
end

function NS.OpenSettings()
	if not NS.RegisterSettings() then
		NS.Print(L["The settings page is not available on this client; use the /qam commands."])
		return false
	end
	local category = NS.settingsCategory
	local id = (category.GetID and category:GetID()) or category
	local ok, err = pcall(Settings.OpenToCategory, id)
	if not ok then
		NS.WarnOnce("settings-open", err)
		return false
	end
	return true
end

NS.RegisterEvent("PLAYER_LOGIN", function()
	NS.RegisterSettings()
end)
