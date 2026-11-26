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
local fit = { rewardMode = 'fit', manualQuality = 3, fallbackToValue = true }

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

-- Tier 5: nothing is an upgrade -> the best CASH item, wearable or not.
-- "Collecting Memories" on a L14 leather wearer: Tunneler's Boots 4s69c (plate, cannot
-- wear), Dusty Mining Gloves 2s58c (leather, no stats the class values), Worn Miner's
-- Waistcord 2s81c (cloth). With no stats anywhere nothing upgrades; the boots must win.
local function trash(index, subclass, sellPrice)
	local c = armour(index, subclass, {}, sellPrice)
	c.equipLoc = ({ 'INVTYPE_FEET', 'INVTYPE_HAND', 'INVTYPE_WAIST' })[index]
	return c
end
choices = { trash(1, A.PLATE, 469), trash(2, A.LEATHER, 258), trash(3, A.CLOTH, 281) }
d = Rewards.Evaluate(choices, fit, player('ROGUE', 14))
assert(d.index == 1 and d.reason == 'fallback' and d.tier == 'tier5Action', 'tier 5 must take the most valuable item even when it is unwearable: ' .. tostring(d.index))
print('PASS tier 5 picks the best cash item regardless of wearability')

-- Tier 5 "ask" leaves the window open with the coin on the cash item; "upgrade" is
-- meaningless there and behaves as cash.
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier5Action = 'ask' }, player('ROGUE', 14))
assert(d.reason == 'recommend' and d.tier == 'tier5Action' and d.choice.index == 1 and not d.index)
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier5Action = 'upgrade' }, player('ROGUE', 14))
assert(d.index == 1 and d.reason == 'fallback')
print('PASS tier 5 ask / upgrade dispositions')

-- The three verbs on tier 4: upgrade takes the best upgrade, cash takes the most
-- valuable item in the whole pool (here the unwearable one), ask recommends.
choices = { armour(1, A.LEATHER, { ARMOR = 6 }, 10), armour(2, A.LEATHER, { ARMOR = 21 }, 20), armour(3, A.MAIL, { ARMOR = 50 }, 900) }
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier4Action = 'upgrade' }, player('SHAMAN', 1))
assert(d.index == 2 and d.reason == 'fit' and d.tier == 'tier4Action', 'tier 4 upgrade -> best upgrade')
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier4Action = 'cash' }, player('SHAMAN', 1))
assert(d.index == 3 and d.reason == 'fallback' and d.tier == 'tier4Action', 'tier 4 cash -> most valuable in pool')
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier4Action = 'ask' }, player('SHAMAN', 1))
assert(d.reason == 'recommend' and d.choice.index == 2 and not d.index, 'tier 4 ask -> recommend')
print('PASS ask / upgrade / cash verbs on tier 4')

-- Saved values from before the rename still mean what they meant.
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier4Action = 'auto' }, player('SHAMAN', 1))
assert(d.index == 2 and d.reason == 'fit', 'legacy auto on tier 4 = upgrade')
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier4Action = 'recommend' }, player('SHAMAN', 1))
assert(d.reason == 'recommend', 'legacy recommend = ask')
choices = { trash(1, A.PLATE, 469), trash(2, A.LEATHER, 258) }
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier5Action = 'auto' }, player('ROGUE', 14))
assert(d.index == 1 and d.reason == 'fallback', 'legacy auto on tier 5 = cash')
print('PASS legacy auto / recommend values map to the new verbs')

-- Druid weapon DPS differs per flavour: Forever form damage IS based on weapon DPS
-- (default MELEE_DPS 4.0 stays), Classic Era form damage IGNORES it (Era client
-- overrides it to 0). A plain-DPS mace is an upgrade for the Forever druid and
-- vendor cash for the Era druid.
local function mace(index, dps, sellPrice)
	return { index = index, itemID = 2000 + index, loaded = true, lootType = Rewards.LOOT_ITEM, quality = 1,
		sellPrice = sellPrice, count = 1, stats = { DAMAGE_PER_SECOND = dps }, usable = true,
		classID = Rules.CLASS_WEAPON, subclassID = Rules.WEAPON.MACE1H, equipLoc = 'INVTYPE_WEAPON', itemLevel = 20 }
end
local gun = { index = 2, itemID = 2002, loaded = true, lootType = Rewards.LOOT_ITEM, quality = 1, sellPrice = 900, count = 1,
	stats = { DAMAGE_PER_SECOND = 12 }, usable = true, classID = Rules.CLASS_WEAPON, subclassID = Rules.WEAPON.GUN, equipLoc = 'INVTYPE_RANGEDRIGHT', itemLevel = 20 }
assert(Rules.WEIGHTS.DRUID.MELEE_DPS == 4.0, 'Forever default: druid weapon DPS counts')
choices = { mace(1, 9.5, 300), gun }
d = Rewards.Evaluate(choices, fit, player('DRUID', 20))
assert(d.index == 1 and d.reason == 'fit' and d.tier == 'tier2Action', 'Forever druid: the hammer is a DPS upgrade -> take it')
print('PASS Forever druid: hammer with better weapon DPS is an upgrade')

-- Apply what Client_ClassicEra.StatWeightOverrides returns.
local eraNS = { SafeNumber = NS.SafeNumber, SafeString = NS.SafeString, SafeBool = function(v) return v == true end,
	Call = function() return nil end, WarnOnce = function() end, Client = { FREQUENCY_DEFAULT = 'default', DecodeFrequency = function() return 'default' end }, ClientFlavours = {} }
assert(loadfile('QuestAutomator/Client/Client_ClassicEra.lua'))('QuestAutomator', eraNS)
local eraOverrides = eraNS.ClientFlavours.classic_era.StatWeightOverrides()
assert(eraOverrides.DRUID and eraOverrides.DRUID.MELEE_DPS == 0, 'Era client must zero druid melee DPS')
local savedDPS, savedHit = Rules.WEIGHTS.DRUID.MELEE_DPS, Rules.WEIGHTS.DRUID.MELEE_HIT
Rules.ApplyClientWeightOverrides(eraOverrides)
assert(Rules.WEIGHTS.DRUID.MELEE_DPS == 0 and Rules.WEIGHTS.ROGUE.MELEE_DPS == 4.0, 'override touches only the listed class/stat')
choices = { mace(1, 9.5, 300), gun }
d = Rewards.Evaluate(choices, fit, player('DRUID', 20))
assert(d.index == 2 and d.reason == 'fallback' and d.tier == 'tier5Action', 'Era druid: hammer DPS is worthless -> no upgrade -> best cash item (the gun)')
assert(choices[1].fit.why == 'nostats')
Rules.WEIGHTS.DRUID.MELEE_DPS, Rules.WEIGHTS.DRUID.MELEE_HIT = savedDPS, savedHit
print('PASS Classic Era druid: weapon DPS ignored, hammer is not an upgrade')

-- Classic Era item stats: C_Item.GetItemStats and C_TooltipInfo do not exist there
-- (in-game 1.15.9: "attempt to index global 'C_TooltipInfo' (a nil value)"); the
-- legacy GetItemStats(link) global is the only source and DOES report the weapon DPS
-- and armour pseudo-stats. Regression: every Era reward scored 0 DPS / 0 armour.
local eraClientNS = { SafeNumber = NS.SafeNumber, SafeString = NS.SafeString, SafeBool = function(v) return v == true end,
	WarnOnce = function() end, ClientFlavours = {},
	Call = function(path, link)
		if path == 'GetItemStats' then
			if link == 'item:2092' then return {} end -- uncached item: empty table
			return { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2.3809523582458, ITEM_MOD_STAMINA_SHORT = 1, RESISTANCE0_NAME = 45 }
		end
		error('Era client reached a non-Era API: ' .. tostring(path))
	end }
assert(loadfile('QuestAutomator/Client/Client.lua'))('QuestAutomator', eraClientNS)
assert(loadfile('QuestAutomator/Client/Client_ClassicEra.lua'))('QuestAutomator', eraClientNS)
local eraItemStats = eraClientNS.ClientFlavours.classic_era.ItemStats
local bow = eraItemStats('item:2504')
assert(bow and math.abs(bow.DAMAGE_PER_SECOND - 2.38) < 0.01 and bow.STAMINA == 1 and bow.ARMOR == 45, 'Era ItemStats must normalise legacy GetItemStats incl. DPS and armour')
assert(eraItemStats('item:2092') == nil, 'uncached item (empty table) -> nil, not {}')
assert(eraItemStats(nil) == nil)
print('PASS Classic Era ItemStats reads legacy GetItemStats (DPS, armour, stats)')

-- The hand-in announcement (Rewards.Describe) must state the cash value whenever
-- the pick was made for cash, and the score + gain whenever it was an upgrade.
NS.FormatMoney = function(copper) return string.format('%dc', copper) end
choices = { trash(1, A.PLATE, 469), trash(2, A.LEATHER, 258) }
d = Rewards.Evaluate(choices, fit, player('ROGUE', 14))
assert(Rewards.Describe(d) == 'no item upgrade, most valuable: 469c', Rewards.Describe(d))
choices = { armour(1, A.LEATHER, { ARMOR = 6 }, 10), armour(2, A.LEATHER, { ARMOR = 21 }, 20), armour(3, A.MAIL, { ARMOR = 50 }, 900) }
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier4Action = 'cash' }, player('SHAMAN', 1))
assert(Rewards.Describe(d) == 'cash over an upgrade (your tier setting), most valuable: 900c', Rewards.Describe(d))
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier4Action = 'upgrade' }, player('SHAMAN', 1))
local text = Rewards.Describe(d)
assert(text:find('^upgrade %(best of several upgrades%): score 2%.1, empty slot') and text:find('%+21 Armor'), text)
print('PASS announce text: cash value on cash picks, score and gain on upgrades')

-- Consumables: Keeper of the Flame offers two potions. Nothing is equipment, so the
-- offer is AMBIGUOUS (tier 1, same bucket as trinkets): ask by default, coin on the
-- most valuable as a hint. "upgrade" has no meaning there and acts as cash.
local function potion(index, sellPrice)
	return { index = index, itemID = 3000 + index, loaded = true, lootType = Rewards.LOOT_ITEM, quality = 1,
		sellPrice = sellPrice, count = 1, stats = {}, usable = true, classID = 0, subclassID = 1, equipLoc = '', itemLevel = 15 }
end
choices = { potion(1, 30), potion(2, 15) }
d = Rewards.Evaluate(choices, fit, player('ROGUE', 14))
assert(d.reason == 'recommend' and d.tier == 'tier1Action' and d.choice.index == 1 and not d.index, 'only consumables -> tier 1 ask, coin on the pricier potion')
assert(choices[1].fit.why == 'notgear' and choices[2].fit.why == 'notgear')
assert(Rewards.ReasonText('recommend', d) == 'ambiguous rewards, make a manual selection')
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier1Action = 'cash' }, player('ROGUE', 14))
assert(d.index == 1 and d.reason == 'fallback' and d.tier == 'tier1Action', 'tier 1 cash -> take the pricier potion')
d = Rewards.Evaluate(choices, { rewardMode = 'fit', fallbackToValue = true, tier1Action = 'upgrade' }, player('ROGUE', 14))
assert(d.index == 1 and d.reason == 'fallback', 'tier 1 upgrade on consumables acts as cash')
print('PASS all-consumable offers are ambiguous (tier 1)')

-- A potion beside real gear does not hijack the pipeline: the gloves are the
-- single upgrade and are taken; the potion is simply not gear.
choices = { potion(1, 900), armour(2, A.LEATHER, { ARMOR = 21 }, 20) }
d = Rewards.Evaluate(choices, fit, player('ROGUE', 14))
assert(d.index == 2 and d.reason == 'fit' and d.tier == 'tier2Action' and choices[1].fit.why == 'notgear', 'gear beside a potion still goes through the upgrade tiers')
print('PASS mixed consumable + gear offers use the upgrade pipeline')

-- Weapons are ORDINARY gear: no "pick weapons" setting, no special hand-off.
-- "Old Ironforge Incursion" on a L8 shaman: Calibrated Blunderbuss (gun, cannot wear),
-- Ironforge Greathammer (2H mace, +7 DPS over the worn staff, untrained but learnable),
-- Deepblaze (wand, cannot wear). The hammer is the ONE upgrade -> tier 2, taken.
-- Regression: the removed KINDS guard flagged this as tier 1 "ambiguous".
local function weapon(index, subclass, equipLoc, dps, sellPrice)
	return { index = index, itemID = 4000 + index, loaded = true, lootType = Rewards.LOOT_ITEM, quality = 2,
		sellPrice = sellPrice, count = 1, stats = { DAMAGE_PER_SECOND = dps }, usable = true,
		classID = Rules.CLASS_WEAPON, subclassID = subclass, equipLoc = equipLoc, itemLevel = 18 }
end
choices = { weapon(1, Rules.WEAPON.GUN, 'INVTYPE_RANGEDRIGHT', 10, 979), weapon(2, Rules.WEAPON.MACE2H, 'INVTYPE_2HWEAPON', 16, 1637), weapon(3, Rules.WEAPON.WAND, 'INVTYPE_RANGEDRIGHT', 9, 986) }
d = Rewards.Evaluate(choices, { rewardMode = 'fit', manualQuality = 3, fallbackToValue = true }, player('SHAMAN', 8))
assert(d.index == 2 and d.reason == 'fit' and d.tier == 'tier2Action', 'lone weapon upgrade beside unwearable weapons -> tier 2, taken: ' .. tostring(d.tier) .. ' ' .. tostring(d.reason))
assert(choices[1].fit.why == 'cannotwear' and choices[3].fit.why == 'cannotwear')
print('PASS weapons follow the 1/2/3 rule: one weapon upgrade is auto-taken')

-- Two weapon upgrades -> tier 4 like any two armour upgrades.
choices = { weapon(1, Rules.WEAPON.MACE2H, 'INVTYPE_2HWEAPON', 16, 100), weapon(2, Rules.WEAPON.AXE2H, 'INVTYPE_2HWEAPON', 15, 100) }
d = Rewards.Evaluate(choices, { rewardMode = 'fit', manualQuality = 3, fallbackToValue = true }, player('SHAMAN', 8))
assert(d.reason == 'recommend' and d.tier == 'tier4Action' and d.upgrades == 2 and d.choice.index == 1, 'two weapon upgrades -> tier 4')
print('PASS two weapon upgrades are tier 4')

-- A trinket among the upgrades is ALWAYS ambiguous (tier 1), no setting involved.
local trinket = armour(1, A.MISC or 0, { STAMINA = 5 }, 100); trinket.equipLoc = 'INVTYPE_TRINKET'
choices = { trinket, armour(2, A.LEATHER, { ARMOR = 21 }, 20) }
d = Rewards.Evaluate(choices, { rewardMode = 'fit', manualQuality = 3, fallbackToValue = true }, player('ROGUE', 14))
assert(d.reason == 'recommend' and d.tier == 'tier1Action', 'trinket among the upgrades -> tier 1 ask: ' .. tostring(d.tier) .. ' ' .. tostring(d.reason))
print('PASS a trinket is always ambiguous (tier 1)')