-- Pure Rewards.Evaluate tier tests: no frames, timers, or WoW API calls.
-- Run from workspace root: lua5.1 QuestAutomator/tests/reward_tiers.lua
local NS = {
	L = setmetatable({}, {__index = function(_, key) return key end}),
	RegisterEvent = function() end,
	Safe = function(v) return v end,
	SafeNumber = function(v) if type(v) == 'number' then return v end return nil end,
	SafeString = function(v) if type(v) == 'string' then return v end return nil end,
	-- FitScore names the armour type for display (C_Item.GetItemSubClassInfo); nothing else may hit the client.
	Call = function(path)
		if path == 'C_Item.GetItemSubClassInfo' then return nil end
		error('reward engine attempted a client API call: ' .. tostring(path))
	end,
}
assert(loadfile('QuestAutomator/Rules.lua'))('QuestAutomator', NS)
assert(loadfile('QuestAutomator/Rewards.lua'))('QuestAutomator', NS)
local Rules, Rewards = NS.Rules, NS.Rewards
local A = Rules.ARMOR

-- No GetInventoryItemLink in this environment: Rewards.WornItem returns nil, which the
-- engine treats like an empty slot (any positive stat value is an upgrade).
local function armour(index, subclass, stats, sellPrice)
	return { index = index, itemID = 1000 + index, loaded = true, lootType = Rewards.LOOT_ITEM, quality = 1,
		sellPrice = sellPrice or 100, count = 1, stats = stats, usable = true,
		classID = Rules.CLASS_ARMOR, subclassID = subclass, equipLoc = 'INVTYPE_HAND', itemLevel = 5 }
end
local function player(class, level)
	return { class = class, level = level, preferredArmor = Rules.PreferredArmor(class, level), weights = Rules.Weights(class) }
end
local fit = { rewardMode = 'fit', manualQuality = 3, weapons = true, trinkets = true, fallbackToValue = true }

-- Dwarven Outfitters on a level-1 shaman: cloth (6 armour), leather (21 armour), mail (cannot wear).
local choices = { armour(1, A.CLOTH, { ARMOR = 6 }, 4), armour(2, A.LEATHER, { ARMOR = 21 }, 6), armour(3, A.MAIL, { ARMOR = 21 }, 7) }
local d = Rewards.Evaluate(choices, fit, player('SHAMAN', 1))
assert(d.index == 2 and d.reason == 'fit' and d.tier == 'tier2Action', 'leather must be the single tier-2 upgrade: ' .. tostring(d.tier) .. ' ' .. tostring(d.reason))
assert(choices[1].fit.sidelined and choices[1].fit.why == 'lighter' and choices[1].fit.lighter, 'cloth must be sidelined as lighter')
assert(choices[1].fit.score == 0 and choices[1].upgrade == false)
assert(not choices[2].fit.lighter and choices[2].upgrade == true)
assert(choices[3].fit.why == 'cannotwear')
print('PASS lighter armour does not compete with a best-type upgrade (tier 2, auto)')

-- Two best-type upgrades are still tier 4 (recommend).
choices = { armour(1, A.LEATHER, { ARMOR = 6 }), armour(2, A.LEATHER, { ARMOR = 21 }), armour(3, A.CLOTH, { ARMOR = 30 }) }
d = Rewards.Evaluate(choices, fit, player('SHAMAN', 1))
assert(d.reason == 'recommend' and d.tier == 'tier4Action' and d.upgrades == 2 and d.choice.index == 2, 'two leather upgrades -> tier 4, coin on the bigger one')
assert(choices[3].fit.why == 'lighter')
print('PASS best-type upgrades alone decide tier 4; lighter piece is sidelined')

-- Only lighter armour on offer: it still competes (lenient rule), single piece -> tier 2.
choices = { armour(1, A.CLOTH, { ARMOR = 6 }), armour(2, A.MAIL, { ARMOR = 21 }) }
d = Rewards.Evaluate(choices, fit, player('SHAMAN', 1))
assert(d.index == 1 and d.reason == 'fit' and d.tier == 'tier2Action', 'lone cloth upgrade still taken when nothing of the best type is offered')
assert(choices[1].fit.lighter and not choices[1].fit.sidelined)
print('PASS lighter armour competes when no best-type upgrade exists')

-- Two lighter pieces and no best type: tier 4 as before.
choices = { armour(1, A.CLOTH, { ARMOR = 6 }), armour(2, A.CLOTH, { ARMOR = 9 }) }
d = Rewards.Evaluate(choices, fit, player('SHAMAN', 1))
assert(d.reason == 'recommend' and d.tier == 'tier4Action' and d.choice.index == 2)
print('PASS two lighter upgrades without a best-type one remain tier 4')

-- Neutral slots are never lighter; a caster's cloth is its best type.
choices = { armour(1, A.CLOTH, { ARMOR = 6 }), armour(2, A.LEATHER, { ARMOR = 21 }) }
d = Rewards.Evaluate(choices, fit, player('MAGE', 1))
assert(d.index == 1 and d.tier == 'tier2Action' and not choices[1].fit.lighter and choices[2].fit.why == 'cannotwear')
local cloak = armour(1, A.CLOTH, { ARMOR = 10 }); cloak.equipLoc = 'INVTYPE_CLOAK'
assert(Rewards.FitScore(cloak, player('WARRIOR', 1), fit).lighter == nil, 'cloak is a neutral slot, not lighter')
print('PASS best-type and neutral-slot armour never flagged lighter')

assert(Rewards.ReasonText('lighter') == 'lighter than your armour class')
print('PASS /qam why text for lighter')