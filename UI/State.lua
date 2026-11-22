-- UI-owned state only. No hooks, replacements, or overrides of automation APIs.
local ADDON, NS = ...
local L = NS.L
local UIState = {}
NS.UIState = UIState

UIState.DEFAULTS = {
	prePickUI = true, prePickUnlocked = false,
	-- Tier dispositions (UIState.TIER_ACTIONS). Three explicit verbs; "auto" was
	-- ambiguous because it meant "take the upgrade" on tiers 2/4 and "take the cash"
	-- on tier 5, which is how the two got confused.
	--   ask     = recommend only: glow the suggested item, window stays open
	--   upgrade = auto-pick the best stat upgrade over what is worn
	--   cash    = auto-pick the highest vendor-value reward, wearable or not
	tier1Action = "ask", tier2Action = "upgrade", tier3Action = "upgrade",
	tier4Action = "ask", tier5Action = "cash",
	-- upgradeBand: "upgrade threshold" - percent more stat value than the worn item a
	-- reward needs before it counts as an upgrade (below it = sidegrade = vendor trash).
	ilvlBand = 2, upgradeBand = 5, weaponProficiency = "learnable", valueSource = "vendor",
}
UIState.TIER_ACTIONS = { "ask", "upgrade", "cash" }
UIState.TIER_ACTION_SET = { ask = true, upgrade = true, cash = true }
-- Saved values from before the rename: "recommend" -> ask; "auto" -> whatever that
-- tier's auto meant (upgrade on 1/2/3/4, cash on 5).
UIState.LEGACY_TIER_ACTIONS = {
	recommend = function() return "ask" end,
	auto = function(tier) return tier == 5 and "cash" or "upgrade" end,
}
function UIState.MigrateTierAction(tier, value)
	if UIState.TIER_ACTION_SET[value] then return value end
	local legacy = UIState.LEGACY_TIER_ACTIONS[value]
	if legacy then return legacy(tier) end
	return UIState.DEFAULTS["tier" .. tier .. "Action"]
end
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
		settings[key] = UIState.MigrateTierAction(tier, settings[key])
	end
	if settings.weaponProficiency ~= "learnable" and settings.weaponProficiency ~= "usable" then settings.weaponProficiency = "learnable" end
	if settings.valueSource ~= "vendor" and settings.valueSource ~= "auction" and settings.valueSource ~= "disenchant" then settings.valueSource = "vendor" end
	settings.ilvlBand = math.max(0, math.min(10, math.floor(settings.ilvlBand)))
	settings.upgradeBand = math.max(0, math.min(50, math.floor(settings.upgradeBand)))
end

NS.RegisterEvent("ADDON_LOADED", function(name)
	if name == ADDON then UIState.Initialize() end
end)