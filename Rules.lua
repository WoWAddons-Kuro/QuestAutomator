-- QuestAutomator: what fits a class. Armour proficiency by level, weapon
-- proficiency and stat weights for the nine Forever classes, the per-character
-- stat override, and the player context handed to the reward scorer.
--
-- The profiles encode the classic (vanilla) rules from memory: warriors and
-- paladins wear mail until level 40 and plate from 40, hunters and shamans wear
-- leather until 40 and mail from 40, rogues and druids leather, the three
-- casters cloth. Anyone can wear a lighter armour class than their best one.
-- Weights are per stat point and spec-agnostic; `/qam stats` overrides them.
local ADDON, NS = ...
local L = NS.L
local Rules = {}
NS.Rules = Rules

-- Enum.ItemArmorSubclass / Enum.ItemWeaponSubclass values from
-- ItemConstantsDocumentation.lua (build 69893).
Rules.ARMOR = { GENERIC = 0, CLOTH = 1, LEATHER = 2, MAIL = 3, PLATE = 4, COSMETIC = 5, SHIELD = 6, LIBRAM = 7, IDOL = 8, TOTEM = 9, SIGIL = 10, RELIC = 11 }
Rules.WEAPON = { AXE1H = 0, AXE2H = 1, BOW = 2, GUN = 3, MACE1H = 4, MACE2H = 5, POLEARM = 6, SWORD1H = 7, SWORD2H = 8,
	WARGLAIVE = 9, STAFF = 10, BEARCLAW = 11, CATCLAW = 12, FIST = 13, GENERIC = 14, DAGGER = 15, THROWN = 16, CROSSBOW = 18, WAND = 19, FISHINGPOLE = 20 }
Rules.CLASS_ARMOR = 4  -- Enum.ItemClass.Armor
Rules.CLASS_WEAPON = 2 -- Enum.ItemClass.Weapon

local A, W = Rules.ARMOR, Rules.WEAPON

-- Highest armour class the class can wear, by the level it becomes available.
Rules.ARMOR_PROGRESSION = {
	WARRIOR = { { 1, A.MAIL }, { 40, A.PLATE } },
	PALADIN = { { 1, A.MAIL }, { 40, A.PLATE } },
	HUNTER  = { { 1, A.LEATHER }, { 40, A.MAIL } },
	SHAMAN  = { { 1, A.LEATHER }, { 40, A.MAIL } },
	ROGUE   = { { 1, A.LEATHER } },
	DRUID   = { { 1, A.LEATHER } },
	MAGE    = { { 1, A.CLOTH } },
	PRIEST  = { { 1, A.CLOTH } },
	WARLOCK = { { 1, A.CLOTH } },
}

Rules.SHIELD_CLASSES = { WARRIOR = true, PALADIN = true, SHAMAN = true }
Rules.RELIC_CLASS = { [A.LIBRAM] = "PALADIN", [A.IDOL] = "DRUID", [A.TOTEM] = "SHAMAN" }

-- Slots where the armour class does not matter (cloaks are "cloth" for everyone).
Rules.NEUTRAL_SLOTS = {
	INVTYPE_CLOAK = true, INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true,
	INVTYPE_HOLDABLE = true, INVTYPE_TABARD = true, INVTYPE_BODY = true, INVTYPE_BAG = true,
}

-- Weapon proficiency: 1 = a natural weapon for the class, lower = usable but
-- not what the class wants, absent = cannot use.
Rules.WEAPONS = {
	WARRIOR = { [W.AXE1H] = 1, [W.AXE2H] = 1, [W.MACE1H] = 1, [W.MACE2H] = 1, [W.SWORD1H] = 1, [W.SWORD2H] = 1, [W.POLEARM] = 1,
		[W.DAGGER] = 0.8, [W.STAFF] = 0.7, [W.FIST] = 0.9, [W.BOW] = 0.5, [W.GUN] = 0.5, [W.CROSSBOW] = 0.5, [W.THROWN] = 0.5 },
	PALADIN = { [W.AXE1H] = 1, [W.AXE2H] = 1, [W.MACE1H] = 1, [W.MACE2H] = 1, [W.SWORD1H] = 1, [W.SWORD2H] = 1, [W.POLEARM] = 1 },
	HUNTER  = { [W.BOW] = 1, [W.GUN] = 1, [W.CROSSBOW] = 1, [W.AXE1H] = 0.7, [W.AXE2H] = 0.7, [W.SWORD1H] = 0.7, [W.SWORD2H] = 0.7,
		[W.POLEARM] = 0.7, [W.DAGGER] = 0.7, [W.STAFF] = 0.7, [W.FIST] = 0.7, [W.THROWN] = 0.5 },
	ROGUE   = { [W.DAGGER] = 1, [W.SWORD1H] = 0.9, [W.MACE1H] = 0.8, [W.FIST] = 0.8, [W.BOW] = 0.4, [W.GUN] = 0.4, [W.CROSSBOW] = 0.4, [W.THROWN] = 0.5 },
	PRIEST  = { [W.MACE1H] = 1, [W.STAFF] = 1, [W.DAGGER] = 1, [W.WAND] = 0.9 },
	SHAMAN  = { [W.MACE1H] = 1, [W.MACE2H] = 1, [W.AXE1H] = 1, [W.AXE2H] = 1, [W.STAFF] = 1, [W.DAGGER] = 1, [W.FIST] = 1 },
	MAGE    = { [W.STAFF] = 1, [W.DAGGER] = 1, [W.SWORD1H] = 1, [W.WAND] = 0.9 },
	WARLOCK = { [W.STAFF] = 1, [W.DAGGER] = 1, [W.SWORD1H] = 1, [W.WAND] = 0.9 },
	DRUID   = { [W.STAFF] = 1, [W.MACE1H] = 1, [W.MACE2H] = 1, [W.DAGGER] = 1, [W.FIST] = 1, [W.POLEARM] = 0.6 },
}

-- Stat keys: the middle part of the ITEM_MOD_<KEY>[_SHORT] global strings.
Rules.STAT_KEYS = {
	"STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT",
	"ATTACK_POWER", "RANGED_ATTACK_POWER", "FERAL_ATTACK_POWER",
	"SPELL_POWER", "SPELL_DAMAGE_DONE", "SPELL_HEALING_DONE",
	"MANA_REGENERATION", "HEALTH_REGENERATION",
	"DEFENSE_SKILL_RATING", "DODGE_RATING", "PARRY_RATING", "BLOCK_RATING", "BLOCK_VALUE",
	"HIT_RATING", "CRIT_RATING", "HASTE_RATING",
	"MANA", "HEALTH",
}
-- Pseudo-stats read from the tooltip, not ITEM_MOD_ strings.
Rules.EXTRA_KEYS = { "ARMOR", "DAMAGE_PER_SECOND" }

Rules.WEIGHTS = {
	WARRIOR = { STRENGTH = 1.0, STAMINA = 0.8, AGILITY = 0.5, ATTACK_POWER = 0.45, HIT_RATING = 0.8, CRIT_RATING = 0.8,
		DEFENSE_SKILL_RATING = 0.6, DODGE_RATING = 0.6, PARRY_RATING = 0.6, BLOCK_RATING = 0.4, BLOCK_VALUE = 0.2, HEALTH = 0.05, ARMOR = 0.02 },
	PALADIN = { STRENGTH = 0.8, STAMINA = 0.7, INTELLECT = 0.6, SPIRIT = 0.3, AGILITY = 0.2, ATTACK_POWER = 0.35,
		SPELL_POWER = 0.5, SPELL_HEALING_DONE = 0.4, SPELL_DAMAGE_DONE = 0.2, MANA_REGENERATION = 0.5,
		DEFENSE_SKILL_RATING = 0.5, DODGE_RATING = 0.5, PARRY_RATING = 0.5, BLOCK_RATING = 0.4, BLOCK_VALUE = 0.2, HIT_RATING = 0.6, CRIT_RATING = 0.6,
		MANA = 0.03, HEALTH = 0.04, ARMOR = 0.02 },
	HUNTER  = { AGILITY = 1.0, STAMINA = 0.6, INTELLECT = 0.4, STRENGTH = 0.2, SPIRIT = 0.1, ATTACK_POWER = 0.4, RANGED_ATTACK_POWER = 0.5,
		HIT_RATING = 0.8, CRIT_RATING = 0.8, MANA = 0.02, HEALTH = 0.03, ARMOR = 0.01 },
	ROGUE   = { AGILITY = 1.0, STRENGTH = 0.8, STAMINA = 0.6, ATTACK_POWER = 0.45, HIT_RATING = 0.9, CRIT_RATING = 0.8, HEALTH = 0.03, ARMOR = 0.01 },
	PRIEST  = { INTELLECT = 0.8, SPIRIT = 0.8, STAMINA = 0.5, SPELL_POWER = 0.6, SPELL_HEALING_DONE = 0.6, SPELL_DAMAGE_DONE = 0.5,
		MANA_REGENERATION = 0.6, HIT_RATING = 0.5, CRIT_RATING = 0.4, MANA = 0.04, HEALTH = 0.02, ARMOR = 0.005 },
	SHAMAN  = { INTELLECT = 0.7, STRENGTH = 0.6, STAMINA = 0.6, SPIRIT = 0.4, AGILITY = 0.4, ATTACK_POWER = 0.3,
		SPELL_POWER = 0.5, SPELL_HEALING_DONE = 0.4, SPELL_DAMAGE_DONE = 0.4, MANA_REGENERATION = 0.5, HIT_RATING = 0.5, CRIT_RATING = 0.5,
		MANA = 0.03, HEALTH = 0.03, ARMOR = 0.015 },
	MAGE    = { INTELLECT = 1.0, SPIRIT = 0.6, STAMINA = 0.5, SPELL_POWER = 0.6, SPELL_DAMAGE_DONE = 0.6, SPELL_HEALING_DONE = 0.1,
		MANA_REGENERATION = 0.4, HIT_RATING = 0.6, CRIT_RATING = 0.5, MANA = 0.04, HEALTH = 0.02, ARMOR = 0.005 },
	WARLOCK = { INTELLECT = 0.8, STAMINA = 0.7, SPIRIT = 0.5, SPELL_POWER = 0.6, SPELL_DAMAGE_DONE = 0.6, SPELL_HEALING_DONE = 0.1,
		MANA_REGENERATION = 0.4, HIT_RATING = 0.6, CRIT_RATING = 0.5, MANA = 0.04, HEALTH = 0.03, ARMOR = 0.005 },
	DRUID   = { INTELLECT = 0.6, SPIRIT = 0.5, STAMINA = 0.6, STRENGTH = 0.5, AGILITY = 0.5, ATTACK_POWER = 0.3, FERAL_ATTACK_POWER = 0.3,
		SPELL_POWER = 0.5, SPELL_HEALING_DONE = 0.5, SPELL_DAMAGE_DONE = 0.3, MANA_REGENERATION = 0.5, HIT_RATING = 0.4, CRIT_RATING = 0.4,
		MANA = 0.03, HEALTH = 0.03, ARMOR = 0.015 },
}

-- Weapon damage per second counts for every class that can use the weapon.
Rules.DPS_WEIGHT = 0.6

-- Weights of a `/qam stats` override, most important first; stats not listed count nothing.
Rules.OVERRIDE_WEIGHTS = { 1.0, 0.75, 0.55, 0.4, 0.3, 0.25, 0.2, 0.15 }

-- Names players may type for `/qam stats`, in both client languages.
Rules.STAT_ALIASES = {
	str = "STRENGTH", strength = "STRENGTH", ["力量"] = "STRENGTH",
	agi = "AGILITY", agility = "AGILITY", ["敏捷"] = "AGILITY",
	sta = "STAMINA", stam = "STAMINA", stamina = "STAMINA", ["耐力"] = "STAMINA",
	int = "INTELLECT", intellect = "INTELLECT", intelligence = "INTELLECT", ["智力"] = "INTELLECT",
	spi = "SPIRIT", spirit = "SPIRIT", ["精神"] = "SPIRIT",
	ap = "ATTACK_POWER", attackpower = "ATTACK_POWER", ["攻击强度"] = "ATTACK_POWER",
	rap = "RANGED_ATTACK_POWER", ["远程攻击强度"] = "RANGED_ATTACK_POWER",
	sp = "SPELL_POWER", spellpower = "SPELL_POWER", ["法术强度"] = "SPELL_POWER",
	healing = "SPELL_HEALING_DONE", heal = "SPELL_HEALING_DONE", ["治疗"] = "SPELL_HEALING_DONE",
	spelldamage = "SPELL_DAMAGE_DONE", spelldmg = "SPELL_DAMAGE_DONE", ["法术伤害"] = "SPELL_DAMAGE_DONE",
	mp5 = "MANA_REGENERATION", ["法力回复"] = "MANA_REGENERATION",
	hp5 = "HEALTH_REGENERATION",
	defense = "DEFENSE_SKILL_RATING", def = "DEFENSE_SKILL_RATING", ["防御"] = "DEFENSE_SKILL_RATING",
	dodge = "DODGE_RATING", ["躲闪"] = "DODGE_RATING", parry = "PARRY_RATING", ["招架"] = "PARRY_RATING",
	block = "BLOCK_RATING", ["格挡"] = "BLOCK_RATING",
	hit = "HIT_RATING", ["命中"] = "HIT_RATING", crit = "CRIT_RATING", ["爆击"] = "CRIT_RATING", ["暴击"] = "CRIT_RATING",
	haste = "HASTE_RATING", ["急速"] = "HASTE_RATING",
	armor = "ARMOR", armour = "ARMOR", ["护甲"] = "ARMOR", dps = "DAMAGE_PER_SECOND", ["每秒伤害"] = "DAMAGE_PER_SECOND",
	mana = "MANA", ["法力"] = "MANA", health = "HEALTH", ["生命"] = "HEALTH",
}

--------------------------------------------------------------------------------
-- Player context.
--------------------------------------------------------------------------------
function Rules.Class()
	local class = NS.SafeString(NS.Call("UnitClassBase", "player"))
	if class then return class:upper() end
	return nil
end

function Rules.Level()
	return NS.SafeNumber(NS.Call("UnitLevel", "player")) or 1
end

-- The best armour class `class` can wear at `level` (nil for an unknown class).
function Rules.PreferredArmor(class, level)
	local steps = Rules.ARMOR_PROGRESSION[class or ""]
	if not steps then return nil end
	local best
	for _, step in ipairs(steps) do
		if (level or 1) >= step[1] then best = step[2] end
	end
	return best
end

-- How well one armour piece's class suits the player: 1 = the best class
-- available at this level, LIGHTER = wearable but lighter than that (a hunter in
-- cloth), 0 = cannot wear. LIGHTER is low enough that a plain piece of the right
-- class beats a lighter piece with a few points of a wanted stat.
Rules.LIGHTER = 0.35
Rules.NEUTRAL = 0.8

function Rules.ArmorScore(class, level, subclass, equipLoc)
	if subclass == nil then return 0 end
	if Rules.NEUTRAL_SLOTS[equipLoc or ""] or subclass == A.GENERIC then return Rules.NEUTRAL end
	if subclass == A.SHIELD then
		return Rules.SHIELD_CLASSES[class or ""] and 1 or 0
	end
	local relicClass = Rules.RELIC_CLASS[subclass]
	if relicClass then
		return relicClass == class and 1 or 0
	end
	if subclass == A.CLOTH or subclass == A.LEATHER or subclass == A.MAIL or subclass == A.PLATE then
		local preferred = Rules.PreferredArmor(class, level)
		if not preferred then return subclass == A.CLOTH and Rules.LIGHTER or 0 end
		if subclass == preferred then return 1 end
		if subclass < preferred then return Rules.LIGHTER end
		return 0
	end
	return 0.5 -- cosmetic, sigils, relics: no rule, do not exclude
end

function Rules.WeaponScore(class, subclass)
	if subclass == nil then return 0 end
	if subclass == W.FISHINGPOLE then return 0 end
	local table_ = Rules.WEAPONS[class or ""]
	if not table_ then return 0 end
	return table_[subclass] or 0
end

function Rules.IsWeapon(classID, subclassID)
	return classID == Rules.CLASS_WEAPON and subclassID ~= W.FISHINGPOLE
end

-- Trinkets are a personal choice like weapons: their "Use:" effects are not scored.
function Rules.IsTrinket(equipLoc)
	return equipLoc == "INVTYPE_TRINKET"
end

--------------------------------------------------------------------------------
-- Equipment slots. INVTYPE_* (C_Item.GetItemInfoInstant's equipLoc) -> the
-- inventory slot IDs the piece could go into (GetInventoryItemLink). Paired
-- slots list both; the upgrade check compares against the weaker one.
--------------------------------------------------------------------------------
Rules.EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
	INVTYPE_TABARD = { 19 },
}

-- Slots whose contents the engine does not compare (nothing to upgrade, or not gear).
Rules.UNCOMPARED_SLOTS = { INVTYPE_BAG = true, INVTYPE_AMMO = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true, INVTYPE_BODY = true }

-- Weapon subclass -> the vanilla weapon-skill name as the skill list shows it
-- (enUS; C_Item.GetItemSubClassInfo gives the localized subclass name, which the
-- skill list repeats verbatim for most weapons, so this table is the fallback).
Rules.WEAPON_SKILL_NAMES = {
	[W.AXE1H] = "Axes", [W.AXE2H] = "Two-Handed Axes", [W.BOW] = "Bows", [W.GUN] = "Guns",
	[W.MACE1H] = "Maces", [W.MACE2H] = "Two-Handed Maces", [W.POLEARM] = "Polearms",
	[W.SWORD1H] = "Swords", [W.SWORD2H] = "Two-Handed Swords", [W.STAFF] = "Staves",
	[W.FIST] = "Fist Weapons", [W.DAGGER] = "Daggers", [W.THROWN] = "Thrown", [W.CROSSBOW] = "Crossbows", [W.WAND] = "Wands",
}

--------------------------------------------------------------------------------
-- Best-wearable: the only sense of "wearable" the reward engine uses (spec §6.2).
-- Armour: the piece's class is the class's best at this level (mail < 40 then
-- plate for warriors and paladins...), neutral slots always, shields for the shield
-- classes, relics for their class. Lighter armour is NOT wearable here.
-- Weapons: by settings.weaponProficiency - "learnable" (the class can train it:
-- Rules.WEAPONS) or "usable" (the character has the skill now: Client.HasWeaponSkill,
-- falling back to learnable when the client cannot tell).
-- -> true/false, reason string
--------------------------------------------------------------------------------
function Rules.IsBestWearable(c, player, settings)
	if c.usable == false then return false, "unusable" end
	local equipLoc = c.equipLoc or ""
	if c.classID == Rules.CLASS_ARMOR then
		local sub = c.subclassID
		if Rules.NEUTRAL_SLOTS[equipLoc] or sub == A.GENERIC then return true, "neutral" end
		if sub == A.SHIELD then
			if Rules.SHIELD_CLASSES[player.class or ""] then return true, "shield" end
			return false, "noshield"
		end
		local relicClass = Rules.RELIC_CLASS[sub]
		if relicClass then
			if relicClass == player.class then return true, "relic" end
			return false, "otherrelic"
		end
		if sub == A.CLOTH or sub == A.LEATHER or sub == A.MAIL or sub == A.PLATE then
			if player.preferredArmor == nil then return false, "unknownclass" end
			if sub == player.preferredArmor then return true, "bestarmor" end
			if sub < player.preferredArmor then return false, "lighter" end
			return false, "heavier"
		end
		return false, "otherarmor"
	end
	if Rules.IsWeapon(c.classID, c.subclassID) then
		local proficiency = settings and settings.weaponProficiency or "learnable"
		local learnable = Rules.WeaponScore(player.class, c.subclassID) > 0
		if not learnable then return false, "cannotlearn" end
		if proficiency == "usable" then
			local has = NS.Client.HasWeaponSkill(c.subclassID)
			if has == false then return false, "noskill" end
		end
		return true, "weapon"
	end
	return false, "notgear"
end

-- Hard to value (spec tier 1): a trinket, a relic, anything with a Use / proc /
-- unparsed Equip effect, or not equipment at all.
function Rules.IsHardToValue(c)
	if c.classID ~= Rules.CLASS_ARMOR and not Rules.IsWeapon(c.classID, c.subclassID) then return true, "notgear" end
	if Rules.IsTrinket(c.equipLoc) then return true, "trinket" end
	if c.classID == Rules.CLASS_ARMOR and Rules.RELIC_CLASS[c.subclassID] then return true, "relic" end
	if c.hasUseEffect then return true, "use" end
	if c.hasProcEffect then return true, "proc" end
	if c.hasUnknownEquip then return true, "equipeffect" end
	return false
end

--------------------------------------------------------------------------------
-- Weapon kinds. When both kinds are offered, a hunter wants the ranged weapon
-- unless Survival leads its talents, the melee classes want the melee weapon,
-- the casters have no preference. No setting: the talents decide.
--------------------------------------------------------------------------------
Rules.RANGED = { [W.BOW] = true, [W.GUN] = true, [W.CROSSBOW] = true, [W.THROWN] = true, [W.WAND] = true }
Rules.MELEE_CLASSES = { WARRIOR = true, PALADIN = true, ROGUE = true, SHAMAN = true, DRUID = true }
Rules.SURVIVAL_SKILL_LINE = 51 -- SkillLine.db2, build 69893: the hunter Survival tree (TraitGroupDisplayInfo.skillLineID)
Rules.WEAPON_KINDS = { "ranged", "melee" }

function Rules.WeaponCategory(subclass)
	if subclass == nil or subclass == W.FISHINGPOLE then return nil end
	if Rules.RANGED[subclass] then return "ranged" end
	return "melee"
end

function Rules.PreferredWeaponCategory(class, talents)
	if class == "HUNTER" then
		if talents and talents.survivalDominant then return "melee" end
		return "ranged"
	end
	if Rules.MELEE_CLASSES[class or ""] then return "melee" end
	return nil
end

-- Points spent per talent tree, read through the client adapter (Forever: the
-- retail trait system; Era: C_SpecializationInfo tabs). Survival is the group
-- with skill line 51 when the client reports skill lines, else the third group
-- in display order. survivalDominant: more points there than in any other tree.
function Rules.Talents()
	local result = NS.Client.TalentGroups()
	if result.source == "none" or #result.groups == 0 then return result end
	local survival
	for _, g in ipairs(result.groups) do
		if g.skillLineID == Rules.SURVIVAL_SKILL_LINE then survival = g end
	end
	survival = survival or result.groups[NS.Client.SURVIVAL_TAB_INDEX]
	if survival then
		local dominant = survival.spent > 0
		for _, g in ipairs(result.groups) do
			if g ~= survival and g.spent >= survival.spent then dominant = false end
		end
		result.survival = survival
		result.survivalDominant = dominant
	end
	return result
end


-- Stat weights for the player: the character's override when set, else the class profile.
function Rules.Weights(class, override)
	if type(override) == "table" and #override > 0 then
		local weights = {}
		for i, key in ipairs(override) do
			weights[key] = Rules.OVERRIDE_WEIGHTS[i] or Rules.OVERRIDE_WEIGHTS[#Rules.OVERRIDE_WEIGHTS]
		end
		return weights, "override"
	end
	local weights = Rules.WEIGHTS[class or ""]
	if weights then return weights, "class" end
	return { STAMINA = 0.5 }, "unknown"
end

function Rules.Player()
	local class = Rules.Class()
	local level = Rules.Level()
	local override = NS.chardb and NS.chardb.stats or nil
	local weights, source = Rules.Weights(class, override)
	local talents = (class == "HUNTER") and Rules.Talents() or nil
	return {
		class = class,
		level = level,
		preferredArmor = Rules.PreferredArmor(class, level),
		weights = weights,
		weightsSource = source,
		talents = talents,
		weaponKind = Rules.PreferredWeaponCategory(class, talents),
	}
end

--------------------------------------------------------------------------------
-- Names (localized by the client where it can).
--------------------------------------------------------------------------------
function Rules.StatName(key)
	if key == "ARMOR" then return _G["RESISTANCE0_NAME"] or _G["ARMOR"] or L["Armor"] end
	if key == "DAMAGE_PER_SECOND" then return _G["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] or L["damage per second"] end
	local name = _G["ITEM_MOD_" .. key .. "_SHORT"]
	if type(name) == "string" and name ~= "" then return name end
	return key:sub(1, 1) .. key:sub(2):lower():gsub("_", " ")
end

function Rules.ArmorName(subclass)
	if subclass == nil then return "?" end
	local name = NS.SafeString(NS.Call("C_Item.GetItemSubClassInfo", Rules.CLASS_ARMOR, subclass))
	if name then return name end
	for key, value in pairs(A) do
		if value == subclass then return key:sub(1, 1) .. key:sub(2):lower() end
	end
	return tostring(subclass)
end

function Rules.WeaponName(subclass)
	if subclass == nil then return "?" end
	local name = NS.SafeString(NS.Call("C_Item.GetItemSubClassInfo", Rules.CLASS_WEAPON, subclass))
	if name then return name end
	for key, value in pairs(W) do
		if value == subclass then return key:sub(1, 1) .. key:sub(2):lower() end
	end
	return tostring(subclass)
end

--------------------------------------------------------------------------------
-- `/qam stats <stat>...` and status output.
--------------------------------------------------------------------------------
function Rules.ParseStatList(text)
	local keys, unknown = {}, {}
	for word in tostring(text or ""):gmatch("[^%s,]+") do
		local key = Rules.STAT_ALIASES[word:lower()] or Rules.STAT_ALIASES[word]
		if not key then
			local upper = word:upper()
			for _, k in ipairs(Rules.STAT_KEYS) do
				if k == upper then key = k end
			end
			for _, k in ipairs(Rules.EXTRA_KEYS) do
				if k == upper then key = k end
			end
		end
		if key then
			local dup = false
			for _, k in ipairs(keys) do if k == key then dup = true end end
			if not dup then keys[#keys + 1] = key end
		else
			unknown[#unknown + 1] = word
		end
	end
	return keys, unknown
end

function Rules.StatsCommand(rest)
	rest = tostring(rest or ""):match("^%s*(.-)%s*$")
	if rest == "" then
		Rules.PrintProfile()
		return
	end
	if rest:lower() == "default" or rest:lower() == "reset" or rest:lower() == "class" then
		NS.chardb.stats = nil
		NS.Print(L["Stat preference: back to the %s profile."], Rules.Class() or "?")
		Rules.PrintProfile()
		return
	end
	local keys, unknown = Rules.ParseStatList(rest)
	if #unknown > 0 then
		NS.Print(L["Unknown stat: %s"], table.concat(unknown, ", "))
	end
	if #keys > 0 then
		NS.chardb.stats = keys
	end
	Rules.PrintProfile()
end

function Rules.PrintProfile()
	local player = Rules.Player()
	local armour = player.preferredArmor and Rules.ArmorName(player.preferredArmor) or "?"
	local ordered = {}
	for key, weight in pairs(player.weights) do ordered[#ordered + 1] = { key = key, weight = weight } end
	table.sort(ordered, function(a, b)
		if a.weight ~= b.weight then return a.weight > b.weight end
		return a.key < b.key
	end)
	local names = {}
	for i = 1, math.min(5, #ordered) do names[#names + 1] = Rules.StatName(ordered[i].key) end
	NS.Print(L["Profile: %s level %d wears %s; stats wanted: %s%s"], tostring(player.class), player.level, armour,
		table.concat(names, ", "), player.weightsSource == "override" and (" (" .. L["set with /qam stats"] .. ")") or "")
	NS.Print(L["Weapon kind when both are offered: %s"], player.weaponKind and L[player.weaponKind] or L["no preference"])
	if player.talents and player.talents.source == "traits" then
		local bits = {}
		for _, g in ipairs(player.talents.groups) do
			bits[#bits + 1] = string.format("%s %d", tostring(g.name or "?"), g.spent)
		end
		NS.Print(L["Talents: %s"], table.concat(bits, " / "))
	end
end

function Rules.DebugReport()
	local player = Rules.Player()
	NS.Print("Rules: class %s level %d preferred armour %s weights from %s",
		tostring(player.class), player.level, tostring(player.preferredArmor), player.weightsSource)
end
