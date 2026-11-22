-- Quest Automator: what fits a class. Armour proficiency by level, weapon
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

-- Stat point values per class: one point of the stat is worth this much. A reward's
-- value is the weighted sum of its stats (Rewards.StatValue) and is compared with the
-- value of the item worn in the same slot; a stat not listed is worth nothing to the
-- class (spell damage on a hunter). Primary stat ~2, secondary ~1, flavour 0.1-0.3.
Rules.WEIGHTS = {
	WARRIOR = { STRENGTH = 2.2, ATTACK_POWER = 1.0, AGILITY = 1.0, HIT_RATING = 1.5, CRIT_RATING = 1.2, STAMINA = 0.6,
		DEFENSE_SKILL_RATING = 0.6, DODGE_RATING = 0.6, PARRY_RATING = 0.6, BLOCK_RATING = 0.3, BLOCK_VALUE = 0.1, ARMOR = 0.15, HEALTH = 0.05 },
	PALADIN = { STRENGTH = 2.0, ATTACK_POWER = 0.9, INTELLECT = 0.5, SPELL_POWER = 0.8, SPELL_HEALING_DONE = 0.7, SPELL_DAMAGE_DONE = 0.3,
		STAMINA = 0.7, SPIRIT = 0.3, AGILITY = 0.4, MANA_REGENERATION = 0.8, HIT_RATING = 1.0, CRIT_RATING = 1.0,
		DEFENSE_SKILL_RATING = 0.5, DODGE_RATING = 0.5, PARRY_RATING = 0.5, BLOCK_RATING = 0.3, BLOCK_VALUE = 0.1, ARMOR = 0.15, MANA = 0.03, HEALTH = 0.04 },
	HUNTER  = { AGILITY = 2.2, ATTACK_POWER = 1.0, RANGED_ATTACK_POWER = 1.0, HIT_RATING = 1.5, CRIT_RATING = 1.2,
		SPIRIT = 0.3, STAMINA = 0.2, ARMOR = 0.15, INTELLECT = 0.1, STRENGTH = 0.1 },
	ROGUE   = { AGILITY = 2.2, STRENGTH = 1.1, ATTACK_POWER = 1.0, HIT_RATING = 1.5, CRIT_RATING = 1.2, STAMINA = 0.3, ARMOR = 0.1 },
	PRIEST  = { INTELLECT = 1.6, SPIRIT = 1.4, SPELL_POWER = 1.2, SPELL_HEALING_DONE = 1.2, SPELL_DAMAGE_DONE = 0.9,
		MANA_REGENERATION = 1.5, HIT_RATING = 0.8, CRIT_RATING = 0.6, STAMINA = 0.3, MANA = 0.05, ARMOR = 0.05 },
	-- Enhancement (the levelling spec; weapon DPS is weighted 4.0 below, so the stat row
	-- must agree with it). The earlier row was a caster profile - Int 1.4 over Str 1.0 -
	-- and ranked "+4 Sta +4 Int" above "+2 Str +2 Agi +4 Sta" on a 2H staff (owner 2026-11-22).
	SHAMAN  = { STRENGTH = 1.0, AGILITY = 0.8, ATTACK_POWER = 0.5, STAMINA = 0.4, INTELLECT = 0.4, SPIRIT = 0.2,
		SPELL_POWER = 0.3, SPELL_DAMAGE_DONE = 0.3, SPELL_HEALING_DONE = 0.2, MANA_REGENERATION = 0.4,
		HIT_RATING = 0.8, CRIT_RATING = 0.8, MANA = 0.03, ARMOR = 0.1 },
	MAGE    = { INTELLECT = 2.0, SPIRIT = 0.8, SPELL_POWER = 1.2, SPELL_DAMAGE_DONE = 1.2, SPELL_HEALING_DONE = 0.1,
		MANA_REGENERATION = 0.7, HIT_RATING = 1.0, CRIT_RATING = 0.8, STAMINA = 0.3, MANA = 0.05, ARMOR = 0.05 },
	WARLOCK = { INTELLECT = 0.8, STAMINA = 0.9, SPIRIT = 0.5, SPELL_POWER = 1.2, SPELL_DAMAGE_DONE = 1.2, SPELL_HEALING_DONE = 0.1,
		MANA_REGENERATION = 0.6, HIT_RATING = 1.0, CRIT_RATING = 0.8, MANA = 0.05, ARMOR = 0.05 },
	DRUID   = { STRENGTH = 2.0, AGILITY = 1.2, INTELLECT = 0.7, SPIRIT = 0.9, ATTACK_POWER = 0.5, FERAL_ATTACK_POWER = 0.5,
		SPELL_POWER = 0.9, SPELL_HEALING_DONE = 0.9, SPELL_DAMAGE_DONE = 0.5, MANA_REGENERATION = 0.9, HIT_RATING = 0.6, CRIT_RATING = 0.6,
		STAMINA = 0.4, MANA = 0.03, ARMOR = 0.1 },
}

-- Weapon pseudo-stats, by weapon kind (Rules.WeaponCategory). DPS: what the class
-- actually swings or shoots with is worth a lot, the other kind next to nothing.
-- SPEED: the weapon's attack speed in seconds; negative = slower is better
-- (normalised auto-attacks, big-hit specials), positive = faster is better
-- (poisons, Windfury), 0 = does not matter. Stored in WEIGHTS under
-- MELEE_DPS / RANGED_DPS / MELEE_SPEED / RANGED_SPEED so the editor and the
-- per-account overrides treat them like any other stat.
Rules.WEAPON_WEIGHT_KEYS = {
	DPS = { melee = "MELEE_DPS", ranged = "RANGED_DPS" },
	SPEED = { melee = "MELEE_SPEED", ranged = "RANGED_SPEED" },
}
Rules.DPS_DEFAULT = 0.1
do
	local melee  = { WARRIOR = 4.0, ROGUE = 4.0, SHAMAN = 4.0, PALADIN = 4.0, DRUID = 4.0, HUNTER = 0.8 }
	local ranged = { HUNTER = 4.0, PRIEST = 2.5, MAGE = 2.0 }
	local meleeSpeed = { PALADIN = -0.1, HUNTER = -0.1, WARRIOR = -0.1, ROGUE = 0.1, SHAMAN = 0.1 }
	for class, profile in pairs(Rules.WEIGHTS) do
		profile.MELEE_DPS = melee[class] or Rules.DPS_DEFAULT
		profile.RANGED_DPS = ranged[class] or Rules.DPS_DEFAULT
		profile.MELEE_SPEED = meleeSpeed[class] or 0
		profile.RANGED_SPEED = 0
	end
end

-- The table above describes WoW Forever (the primary target). Where the GAME ITSELF
-- works differently on another flavour, the flavour's client file says so through
-- Client.StatWeightOverrides() and it is folded in here, once, at load - so
-- DefaultWeight, the stat-weight grid's grey defaults and Rules.Weights all agree.
-- The known case: druid Cat/Bear damage is based on weapon DPS on Forever (the 4.0
-- above is right) but IGNORES weapon DPS on Classic Era (Era zeroes it).
function Rules.ApplyClientWeightOverrides(overrides)
	if type(overrides) ~= "table" then return end
	for class, row in pairs(overrides) do
		local profile = Rules.WEIGHTS[class]
		if profile and type(row) == "table" then
			for key, weight in pairs(row) do
				if type(weight) == "number" then profile[key] = weight end
			end
		end
	end
end
do
	local Client = NS.Client
	if Client and type(Client.StatWeightOverrides) == "function" then
		Rules.ApplyClientWeightOverrides(Client.StatWeightOverrides())
	end
end

-- The weight of a weapon pseudo-stat ("DPS" or "SPEED") for this player, by the
-- weapon's kind. 0 for a non-weapon.
function Rules.WeaponWeight(player, subclass, which)
	local kind = Rules.WeaponCategory(subclass)
	local keys = Rules.WEAPON_WEIGHT_KEYS[which]
	local key = kind and keys and keys[kind]
	return key and player.weights[key] or 0
end

-- The classes and stats shown in the stat-weight grid (Settings > Stat weights),
-- in display order. CLASSES also fixes row order; EDITABLE_STATS the columns, each
-- with the short header the grid uses.
Rules.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
Rules.EDITABLE_STATS = {
	{ key = "STRENGTH", short = "Str" }, { key = "AGILITY", short = "Agi" }, { key = "STAMINA", short = "Sta" },
	{ key = "INTELLECT", short = "Int" }, { key = "SPIRIT", short = "Spi" },
	{ key = "ATTACK_POWER", short = "AP" }, { key = "RANGED_ATTACK_POWER", short = "RAP" }, { key = "FERAL_ATTACK_POWER", short = "FAP" },
	{ key = "SPELL_POWER", short = "SP" }, { key = "SPELL_DAMAGE_DONE", short = "SpDmg" }, { key = "SPELL_HEALING_DONE", short = "Heal" },
	{ key = "MANA_REGENERATION", short = "MP5" }, { key = "HEALTH_REGENERATION", short = "HP5" },
	{ key = "HIT_RATING", short = "Hit" }, { key = "CRIT_RATING", short = "Crit" }, { key = "HASTE_RATING", short = "Haste" },
	{ key = "DEFENSE_SKILL_RATING", short = "Def" }, { key = "DODGE_RATING", short = "Dodge" }, { key = "PARRY_RATING", short = "Parry" },
	{ key = "BLOCK_RATING", short = "Block" }, { key = "BLOCK_VALUE", short = "BlkV" },
	{ key = "ARMOR", short = "Armor" }, { key = "MANA", short = "Mana" }, { key = "HEALTH", short = "HP" },
	{ key = "MELEE_DPS", short = "mDPS" }, { key = "RANGED_DPS", short = "rDPS" },
	{ key = "MELEE_SPEED", short = "mSpd" }, { key = "RANGED_SPEED", short = "rSpd" },
}

-- User overrides of the class profiles live in NS.db.statWeights[class][key] (account
-- wide). nil = default; a number (0 allowed) replaces the default for that cell.
function Rules.DefaultWeight(class, key)
	local profile = Rules.WEIGHTS[class or ""]
	return profile and profile[key] or 0
end

function Rules.UserWeight(class, key)
	local overrides = NS.db and NS.db.statWeights
	local row = overrides and overrides[class]
	local v = row and row[key]
	if type(v) == "number" then return v end
	return nil
end

function Rules.EffectiveWeight(class, key)
	local v = Rules.UserWeight(class, key)
	if v ~= nil then return v end
	return Rules.DefaultWeight(class, key)
end

-- Sets or clears (value == nil) one override. Values equal to the default are stored
-- as nil so an untouched grid stays empty in the saved variables.
function Rules.SetUserWeight(class, key, value)
	if not NS.db then return end
	NS.db.statWeights = NS.db.statWeights or {}
	local row = NS.db.statWeights[class] or {}
	if value == nil or value == Rules.DefaultWeight(class, key) then value = nil end
	row[key] = value
	if next(row) then NS.db.statWeights[class] = row else NS.db.statWeights[class] = nil end
end

function Rules.ResetUserWeights(class)
	if not NS.db or not NS.db.statWeights then return end
	if class then NS.db.statWeights[class] = nil else NS.db.statWeights = {} end
end

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

--------------------------------------------------------------------------------
-- Weapon training. The class table says what the class can ever learn; the
-- character's skill lines (GetNumSkillLines / GetSkillLineInfo, the Skills panel)
-- say what is trained right now. Skill names are matched against the weapon
-- subclass name the client returns (C_Item.GetItemSubClassInfo), with the plural
-- forms the skill list uses ("Two-Handed Swords" vs subclass "Two-Handed Swords",
-- "Bows" vs "Bows", "Daggers" vs "Daggers"), compared case-insensitively.
--------------------------------------------------------------------------------
Rules.SKILL_LINE_NAMES = {
	[W.AXE1H] = { "Axes", "One-Handed Axes" }, [W.AXE2H] = { "Two-Handed Axes" },
	[W.BOW] = { "Bows" }, [W.GUN] = { "Guns" }, [W.CROSSBOW] = { "Crossbows" },
	[W.MACE1H] = { "Maces", "One-Handed Maces" }, [W.MACE2H] = { "Two-Handed Maces" },
	[W.POLEARM] = { "Polearms" }, [W.SWORD1H] = { "Swords", "One-Handed Swords" }, [W.SWORD2H] = { "Two-Handed Swords" },
	[W.STAFF] = { "Staves" }, [W.FIST] = { "Fist Weapons" }, [W.DAGGER] = { "Daggers" },
	[W.THROWN] = { "Thrown" }, [W.WAND] = { "Wands" },
}

-- Lower-cased skill name -> rank, for every skill line the character has.
function Rules.TrainedSkills()
	if type(GetNumSkillLines) ~= "function" or type(GetSkillLineInfo) ~= "function" then return nil end -- API absent: cannot tell
	local skills = {}
	local n = NS.SafeNumber(NS.Call("GetNumSkillLines"))
	if not n then return nil end
	for i = 1, n do
		local name, isHeader, _, rank = NS.Call("GetSkillLineInfo", i)
		name = NS.SafeString(name)
		if name and not NS.SafeBool(isHeader) then skills[name:lower()] = NS.SafeNumber(rank) or 0 end
	end
	return skills
end

-- true / false, or nil when the client cannot say (no skill API).
function Rules.HasWeaponSkill(subclass)
	local skills = Rules.TrainedSkills()
	if not skills then return nil end
	local names = { NS.SafeString(NS.Call("C_Item.GetItemSubClassInfo", Rules.CLASS_WEAPON, subclass)) }
	for _, alias in ipairs(Rules.SKILL_LINE_NAMES[subclass] or {}) do names[#names + 1] = alias end
	for _, name in ipairs(names) do
		if name and skills[name:lower()] then return true end
	end
	return false
end

-- Trinkets are a personal choice like weapons: their "Use:" effects are not scored.
function Rules.IsTrinket(equipLoc)
	return equipLoc == "INVTYPE_TRINKET"
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

-- Points spent per talent tree of the active combat configuration. Forever runs
-- vanilla-style trees on the retail trait system: the active spec group's config
-- (C_SpecializationInfo.GetCombatConfigIDForSpecGroup, as Camelot's
-- ClassTalentsFrame:SetTab does) has one tree whose three "groups"
-- (C_Traits.GetGroupDisplayInfoByTreeID) are the trees, and
-- C_Traits.GetGroupCurrencyInfo reports the points spent in each (the number the
-- tree headers show). Survival is the group with skill line 51, else the third
-- group in display order. survivalDominant: more points there than in any other tree.
function Rules.Talents()
	local result = { groups = {}, source = "none" }
	local group = NS.SafeNumber(NS.Call("C_SpecializationInfo.GetActiveSpecGroup")) or 1
	local configID = NS.SafeNumber(NS.Call("C_SpecializationInfo.GetCombatConfigIDForSpecGroup", group))
		or NS.SafeNumber(NS.Call("C_ClassTalents.GetActiveConfigID"))
	if not configID then return result end
	local configInfo = NS.Call("C_Traits.GetConfigInfo", configID)
	local treeID = type(configInfo) == "table" and type(configInfo.treeIDs) == "table" and NS.SafeNumber(configInfo.treeIDs[1]) or nil
	if not treeID then return result end
	local displayInfos = NS.Call("C_Traits.GetGroupDisplayInfoByTreeID", treeID)
	if type(displayInfos) ~= "table" or #displayInfos == 0 then return result end
	local groupIDs = {}
	for _, info in ipairs(displayInfos) do
		local id = NS.SafeNumber(info.groupID)
		if id then groupIDs[#groupIDs + 1] = id end
	end
	local spentByGroup = {}
	local currencyInfos = NS.Call("C_Traits.GetGroupCurrencyInfo", configID, groupIDs)
	for _, groupInfo in ipairs(type(currencyInfos) == "table" and currencyInfos or {}) do
		local currency = type(groupInfo.currencyInfos) == "table" and groupInfo.currencyInfos[1] or nil
		local id = NS.SafeNumber(groupInfo.traitNodeGroupID)
		if id then spentByGroup[id] = currency and NS.SafeNumber(currency.spent) or 0 end
	end
	for i, info in ipairs(displayInfos) do
		result.groups[#result.groups + 1] = {
			name = NS.SafeString(info.displayName),
			skillLineID = NS.SafeNumber(info.skillLineID),
			orderIndex = NS.SafeNumber(info.orderIndex) or i,
			spent = spentByGroup[NS.SafeNumber(info.groupID) or 0] or 0,
		}
	end
	table.sort(result.groups, function(a, b) return a.orderIndex < b.orderIndex end)
	result.source = "traits"
	local survival
	for _, g in ipairs(result.groups) do
		if g.skillLineID == Rules.SURVIVAL_SKILL_LINE then survival = g end
	end
	survival = survival or result.groups[3]
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


-- Stat weights for the player: the character's /qam stats list when set, else the
-- class profile with the account's grid overrides applied.
function Rules.Weights(class, override)
	if type(override) == "table" and #override > 0 then
		local weights = {}
		for i, key in ipairs(override) do
			weights[key] = Rules.OVERRIDE_WEIGHTS[i] or Rules.OVERRIDE_WEIGHTS[#Rules.OVERRIDE_WEIGHTS]
		end
		return weights, "override"
	end
	local profile = Rules.WEIGHTS[class or ""]
	if not profile then return { STAMINA = 0.5 }, "unknown" end
	local weights, source = {}, "class"
	for key, value in pairs(profile) do weights[key] = value end
	local user = NS.db and NS.db.statWeights and NS.db.statWeights[class]
	if user then
		for key, value in pairs(user) do
			if type(value) == "number" then weights[key] = value > 0 and value or nil; source = "grid" end
		end
	end
	return weights, source
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
	-- Our own short label: the client's ITEM_MOD_DAMAGE_PER_SECOND_SHORT is "Damage Per Second" and clips in the pick grid.
	if key == "DAMAGE_PER_SECOND" then return L["Weapon DPS"] end
	if key == "ATTACK_SPEED" then return L["Weapon speed"] end
	-- Weapon pseudo-stats of the stat-value editor.
	if key == "MELEE_DPS" then return L["Melee weapon DPS"] end
	if key == "RANGED_DPS" then return L["Ranged weapon DPS"] end
	if key == "MELEE_SPEED" then return L["Melee weapon speed"] end
	if key == "RANGED_SPEED" then return L["Ranged weapon speed"] end
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
