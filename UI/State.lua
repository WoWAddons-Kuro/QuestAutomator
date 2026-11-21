-- UI-owned state only. No hooks, replacements, or overrides of automation APIs.
local ADDON, NS = ...
local L = NS.L
local UIState = {}
NS.UIState = UIState

UIState.DEFAULTS = {
	prePickUI = true, prePickUnlocked = false,
	tier1Action = "recommend", tier2Action = "auto", tier3Action = "auto",
	tier4Action = "recommend", tier5Action = "auto",
	-- upgradeBand: percent more stat value than the worn item a reward needs to count as an upgrade.
	ilvlBand = 2, upgradeBand = 10, weaponProficiency = "learnable", valueSource = "vendor",
}
UIState.TIER_ACTIONS = { "recommend", "auto" }
UIState.WEAPON_PROFICIENCIES = { "learnable", "usable" }
UIState.VALUE_SOURCES = { "vendor", "auction", "disenchant" }

function UIState.PlaceholderLabel(label)
	return label .. " — " .. L["Not implemented — no effect"]
end

function UIState.PlaceholderTip(tip)
	local notice = L["This setting is saved for future use. It does not affect automation or reward selection."]
	if tip and tip ~= "" then return notice .. "\n\n" .. tip end
	return notice
end

-- Core.InitDB runs at ADDON_LOADED, after every TOC file has loaded.
for key, value in pairs(UIState.DEFAULTS) do
	NS.DEFAULT_SETTINGS[key] = value
end

function UIState.Initialize()
	if not NS.db or not NS.chardb then return end
	local settings = NS.db.settings
	for key, default in pairs(UIState.DEFAULTS) do
		if type(settings[key]) ~= type(default) then settings[key] = default end
	end
	for tier = 1, 5 do
		local key = "tier" .. tier .. "Action"
		if settings[key] ~= "auto" and settings[key] ~= "recommend" then settings[key] = UIState.DEFAULTS[key] end
	end
	if settings.weaponProficiency ~= "learnable" and settings.weaponProficiency ~= "usable" then settings.weaponProficiency = "learnable" end
	if settings.valueSource ~= "vendor" and settings.valueSource ~= "auction" and settings.valueSource ~= "disenchant" then settings.valueSource = "vendor" end
	settings.ilvlBand = math.max(0, math.min(10, math.floor(settings.ilvlBand)))
	settings.upgradeBand = math.max(0, math.min(50, math.floor(settings.upgradeBand)))
end

NS.RegisterEvent("ADDON_LOADED", function(name)
	if name == ADDON then UIState.Initialize() end
end)