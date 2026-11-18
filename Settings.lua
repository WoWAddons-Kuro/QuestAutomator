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

	Dropdown(category, "QAM_REWARD_MODE", "rewardMode", NS.REWARD_MODES, NS.RewardModeName,
		L["Reward choice"],
		L["Best fit compares the armour class you wear at your level and the stats your class wants. Most valuable takes the reward with the highest vendor price."])
	Dropdown(category, "QAM_MANUAL_QUALITY", "manualQuality", NS.QUALITY_CHOICES, NS.QualityName,
		L["Leave the choice to me from quality"],
		L["When any reward is of this quality or better, the reward window stays open for you to choose."])
	Checkbox(category, "QAM_WEAPONS", "weapons",
		L["Pick weapons too"],
		L["Off by default: whenever a weapon is among the rewards, the whole choice is left to you. On, weapons are scored by your class's weapon skills and the damage per second."])
	Checkbox(category, "QAM_TRINKETS", "trinkets",
		L["Pick trinkets too"],
		L["Off by default: whenever a trinket is among the rewards, the whole choice is left to you. On, a trinket counts as a neutral-slot item scored by its stats; Use effects are not read."])
	Checkbox(category, "QAM_FALLBACK", "fallbackToValue",
		L["Nothing fits: take the most valuable"],
		L["When no reward is usable by your class, take the one with the highest vendor price instead of leaving the choice to you."])
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
