-- Quest Automator: reading the reward choices of the open quest and
-- picking one. Item facts come from C_Item (GetItemInfoInstant for class,
-- subclass and slot; GetItemInfo for vendor price and item level), the stats
-- from C_Item.GetItemStats when it answers and otherwise from the reward's
-- tooltip (C_TooltipInfo.GetQuestItem) parsed with this build's own
-- ITEM_MOD_* format strings.
local ADDON, NS = ...
local L = NS.L
local Rules = NS.Rules
local format = string.format
local Rewards = {}
NS.Rewards = Rewards

Rewards.LOOT_ITEM = 0     -- GetQuestItemInfoLootType: an item
Rewards.LOOT_CURRENCY = 1 -- a currency (never chosen by the addon)

-- Where the choices are read from. The NPC frame (quest detail and reward panels)
-- and the quest log answer the same questions through different globals, exactly
-- the pairs Mainline\QuestInfo.lua uses (GetQuestItemInfo / GetQuestLogChoiceInfo,
-- GetQuestItemLink / GetQuestLogItemLink, C_TooltipInfo.GetQuestItem / GetQuestLogItem).
-- Choice indices are the ones Blizzard stamps on the reward buttons (SetID), so a
-- decision's index can be matched to a button directly.
Rewards.OFFER = {
	name = "offer",
	Count = function() return NS.Call("GetNumQuestChoices") end,
	LootType = function(i) return NS.Call("GetQuestItemInfoLootType", "choice", i) end,
	Info = function(i) return NS.Call("GetQuestItemInfo", "choice", i) end,
	Link = function(i) return NS.Call("GetQuestItemLink", "choice", i) end,
	Tooltip = function(i) return NS.Call("C_TooltipInfo.GetQuestItem", "choice", i) end,
}

-- The quest log counts item choices only (GetNumQuestLogChoices(questID), the
-- QuestUtils_GetBestQualityItemRewardIndex convention) and indexes them the way
-- QuestInfo.lua numbers its buttons in questLog mode (choiceItemIndex).
-- Reading them differs per client (Forever takes questID, Era reads the selected
-- log entry): Client.QuestLogChoiceSource hides that.
function Rewards.LogSource(questID)
	local source = NS.Client.QuestLogChoiceSource(questID)
	source.LootType = function() return Rewards.LOOT_ITEM end
	return source
end

-- This build's format strings (GlobalStrings on wago.tools, build 1.60.1.69893,
-- enUS and zhCN), used when the client's global is missing or does not match.
-- The client's own value is always tried first.
Rewards.FORMATS = {
	ITEM_MOD_MANA = { "%c%s Mana", "%c%s 法力" },
	ITEM_MOD_HEALTH = { "%c%s Health", "%c%s 生命" },
	ITEM_MOD_AGILITY = { "%c%s Agility", "%c%s 敏捷" },
	ITEM_MOD_STRENGTH = { "%c%s Strength", "%c%s 力量" },
	ITEM_MOD_SPIRIT = { "%c%s Spirit", "%c%s 精神" },
	ITEM_MOD_STAMINA = { "%c%s Stamina", "%c%s 耐力" },
	ITEM_MOD_INTELLECT = { "%c%s Intellect", "%c%s 智力" },
	ITEM_MOD_DEFENSE_SKILL_RATING = { "Increases defense skill by %s.", "防御技能提高%s点。" },
	ITEM_MOD_DODGE_RATING = { "Increases your dodge by %s.", "使你的躲闪提高%s点。" },
	ITEM_MOD_PARRY_RATING = { "Increases your parry by %s.", "使你的招架提高%s点。" },
	ITEM_MOD_BLOCK_RATING = { "Increases your shield block by %s.", "使你的盾牌格挡提高%s点。" },
	ITEM_MOD_HIT_RATING = { "Increases your hit by %s.", "使你的命中提高%s点。" },
	ITEM_MOD_CRIT_RATING = { "Increases your critical strike by %s.", "使你的爆击提高%s点。" },
	ITEM_MOD_HASTE_RATING = { "Increases your haste by %s.", "使你的急速提高%s点。" },
	ITEM_MOD_SPELL_HEALING_DONE = { "Increases healing done by magical spells and effects by up to %s.", "魔法法术和效果的治疗量提高最多%s点。" },
	ITEM_MOD_SPELL_DAMAGE_DONE = { "Increases damage done by magical spells and effects by up to %s.", "魔法法术和效果的伤害量提高最多%s点。" },
	ITEM_MOD_ATTACK_POWER = { "Increases attack power by %s.", "攻击强度提高%s点。" },
	ITEM_MOD_RANGED_ATTACK_POWER = { "Increases ranged attack power by %s.", "远程攻击强度提高%s点。" },
	ITEM_MOD_FERAL_ATTACK_POWER = { "Increases attack power by %s in Cat, Bear, Dire Bear, and Moonkin forms only.", "在猎豹、巨熊、巨熊（增强）和枭兽形态下攻击强度提高%s点。" },
	ITEM_MOD_MANA_REGENERATION = { "Restores %s mana per 5 sec.", "每5秒回复%s点法力值。" },
	ITEM_MOD_HEALTH_REGENERATION = { "Restores %s health per 5 sec.", "每5秒回复%s点生命值。" },
	ITEM_MOD_SPELL_POWER = { "Increases spell power by %s.", "法术强度提高%s点。" },
	ITEM_MOD_BLOCK_VALUE = { "Increases the block value of your shield by %s.", "使你的盾牌格挡值提高%s点。" },
	DPS_TEMPLATE = { "(%s damage per second)", "（每秒伤害%s）" },
	ARMOR_TEMPLATE = { "%s Armor", "%s点护甲" },
	SPEED_TEMPLATE = { "Speed %s", "速度 %s" },
	ITEM_SPELL_TRIGGER_ONEQUIP = { "Equip:", "装备：" },
}

-- Tag -> stat key for the pseudo-stats.
Rewards.TEMPLATE_KEYS = { DPS_TEMPLATE = "DAMAGE_PER_SECOND", ARMOR_TEMPLATE = "ARMOR", SPEED_TEMPLATE = "ATTACK_SPEED" }

--------------------------------------------------------------------------------
-- Format strings -> Lua patterns. "%c" becomes an optional sign, "%s" / "%d" a
-- number; positional forms ("%1$s") are accepted; everything else is literal.
--------------------------------------------------------------------------------
local patternCache = {}

function Rewards.CompilePattern(fmt)
	local cached = patternCache[fmt]
	if cached then return cached.pattern, cached.groups end
	local out, groups = {}, {}
	local i, n = 1, #fmt
	while i <= n do
		local c = fmt:sub(i, i)
		if c == "%" then
			local pos, spec = fmt:match("^%%(%d*%$?)([csd])", i)
			if spec then
				i = i + 2 + #pos
				if spec == "c" then
					out[#out + 1] = "([%+%-]?)"
					groups[#groups + 1] = "sign"
				else
					out[#out + 1] = "([%d,%.]+)"
					groups[#groups + 1] = "number"
				end
			else
				out[#out + 1] = "%%"
				i = i + 1
			end
		else
			if c:match("[%^%$%(%)%.%[%]%*%+%-%?]") then
				out[#out + 1] = "%" .. c
			else
				out[#out + 1] = c
			end
			i = i + 1
		end
	end
	local pattern = "^" .. table.concat(out) .. "$"
	patternCache[fmt] = { pattern = pattern, groups = groups }
	return pattern, groups
end

-- The format strings to try for a tag: the client's global first, then the built-ins.
function Rewards.FormatsFor(tag)
	local list = {}
	local live = _G[tag]
	if type(live) == "string" and live ~= "" then list[#list + 1] = live end
	for _, fmt in ipairs(Rewards.FORMATS[tag] or {}) do
		if fmt ~= live then list[#list + 1] = fmt end
	end
	return list
end

local function StripCodes(text)
	text = tostring(text or "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", "")
	return text:match("^%s*(.-)%s*$")
end

local function ToNumber(sign, digits)
	local cleaned = (digits or ""):gsub(",", "")
	local value = tonumber(cleaned)
	if not value then return nil end
	if sign == "-" then value = -value end
	return value
end

local function MatchFormat(text, fmt)
	local pattern, groups = Rewards.CompilePattern(fmt)
	local a, b = text:match(pattern)
	if a == nil then return nil end
	local sign, digits
	for i, kind in ipairs(groups) do
		local v = (i == 1) and a or b
		if kind == "sign" then sign = v else digits = v end
	end
	return ToNumber(sign, digits)
end

local parseOrder
local function ParseOrder()
	if parseOrder then return parseOrder end
	parseOrder = {}
	for _, key in ipairs(Rules.STAT_KEYS) do
		parseOrder[#parseOrder + 1] = { tag = "ITEM_MOD_" .. key, key = key }
	end
	for tag, key in pairs(Rewards.TEMPLATE_KEYS) do
		parseOrder[#parseOrder + 1] = { tag = tag, key = key }
	end
	return parseOrder
end

-- One tooltip line -> stat key and amount, or nil. "Equip: " prefixes are removed first.
function Rewards.ParseStatLine(text)
	text = StripCodes(text)
	if text == "" then return nil end
	local candidates = { text }
	for _, prefix in ipairs(Rewards.FormatsFor("ITEM_SPELL_TRIGGER_ONEQUIP")) do
		if text:sub(1, #prefix) == prefix then
			candidates[#candidates + 1] = text:sub(#prefix + 1):match("^%s*(.-)%s*$")
		end
	end
	for _, entry in ipairs(ParseOrder()) do
		for _, fmt in ipairs(Rewards.FormatsFor(entry.tag)) do
			for _, candidate in ipairs(candidates) do
				local value = MatchFormat(candidate, fmt)
				if value then return entry.key, value end
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Stats of one reward.
--------------------------------------------------------------------------------
-- C_Item.GetItemStats keys its table by the ITEM_MOD_*_SHORT global-string
-- names (retail behaviour; unverified on Forever, hence the tooltip fallback).
function Rewards.StatsFromAPI(link)
	if not link then return nil end
	local t = NS.Call("C_Item.GetItemStats", link)
	if type(t) ~= "table" then return nil end
	local stats, any = {}, false
	for k, v in pairs(t) do
		k, v = NS.SafeString(k), NS.SafeNumber(v)
		if k and v then
			local key = k:match("^ITEM_MOD_(.+)_SHORT$") or k:match("^ITEM_MOD_(.+)$")
			if k == "RESISTANCE0_NAME" then key = "ARMOR" end
			if key then
				stats[key] = (stats[key] or 0) + v
				any = true
			end
		end
	end
	if any then return stats end
	return nil
end

function Rewards.StatsFromTooltip(index, kind)
	return Rewards.StatsFromTooltipData(NS.Call("C_TooltipInfo.GetQuestItem", kind or "choice", index))
end

function Rewards.StatsFromTooltipData(data)
	if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	local stats, any = {}, false
	for _, line in ipairs(data.lines) do
		if type(line) == "table" then
			-- Both columns: "Speed 2.90" sits in rightText beside the damage range.
			for _, text in ipairs({ NS.SafeString(line.leftText), NS.SafeString(line.rightText) }) do
				local key, value = Rewards.ParseStatLine(text)
				if key then
					stats[key] = (stats[key] or 0) + value
					any = true
				end
			end
		end
	end
	if any then return stats end
	return nil
end

--------------------------------------------------------------------------------
-- The choices of the open reward panel.
--------------------------------------------------------------------------------
function Rewards.Gather(numChoices, source)
	source = source or Rewards.OFFER
	local choices = {}
	for i = 1, numChoices do
		local lootType = NS.SafeNumber(source.LootType(i)) or Rewards.LOOT_ITEM
		local c = { index = i, lootType = lootType, stats = {}, loaded = true, count = 1, quality = 0 }
		if lootType == Rewards.LOOT_ITEM then
			local name, _, count, quality, usable, itemID = source.Info(i)
			c.name = NS.SafeString(name)
			c.count = NS.SafeNumber(count) or 1
			c.quality = NS.SafeNumber(quality) or 0
			c.usable = NS.Safe(usable) ~= false and NS.Safe(usable) ~= 0
			c.itemID = NS.SafeNumber(itemID)
			c.link = NS.SafeString(source.Link(i))
			local ref = c.link or c.itemID
			if ref then
				local id, _, _, equipLoc, _, classID, subclassID = NS.Call("C_Item.GetItemInfoInstant", ref)
				c.itemID = c.itemID or NS.SafeNumber(id)
				c.equipLoc = NS.SafeString(equipLoc)
				c.classID = NS.SafeNumber(classID)
				c.subclassID = NS.SafeNumber(subclassID)
				local iname, _, iquality, ilvl, minLevel, _, _, _, _, _, sellPrice = NS.Call("C_Item.GetItemInfo", ref)
				if NS.SafeString(iname) then
					c.loaded = true
					c.name = c.name or NS.SafeString(iname)
					c.quality = NS.SafeNumber(iquality) or c.quality
					c.itemLevel = NS.SafeNumber(ilvl) or 0
					c.minLevel = NS.SafeNumber(minLevel) or 0
					c.sellPrice = NS.SafeNumber(sellPrice) or 0
				else
					c.loaded = false
				end
				local tooltip = source.Tooltip(i)
				local stats = Rewards.StatsFromAPI(c.link)
				c.statsSource = stats and "api" or nil
				if not stats then
					stats = Rewards.StatsFromTooltipData(tooltip)
					c.statsSource = stats and "tooltip" or "none"
				else
					-- GetItemStats never reports the tooltip-only pseudo-stats (weapon DPS,
					-- armour value) - they are not ITEM_MOD_* entries. Read those from the
					-- tooltip even when the API answered, else every weapon scores 0 DPS.
					local fromTooltip = Rewards.StatsFromTooltipData(tooltip) or {}
					for _, key in ipairs(Rules.EXTRA_KEYS) do
						if stats[key] == nil and fromTooltip[key] then stats[key] = fromTooltip[key] end
					end
				end
				c.stats = stats or {}
			else
				c.loaded = false
			end
		end
		choices[#choices + 1] = c
	end
	return choices
end

--------------------------------------------------------------------------------
-- Scoring.
--------------------------------------------------------------------------------
-- Weapons: the class table says whether the class can ever learn it (else
-- "cannotwear"); the character's skill lines (Rules.HasWeaponSkill) say whether it
-- is trained right now. An untrained-but-learnable weapon is still scored
-- (settings.weaponProficiency == "learnable", the default) or excluded ("usable"),
-- and carries fit.untrained for the UI. isUsable=false is treated the same way.
function Rewards.FitScore(c, player, settings)
	local typeScore, typeName
	local untrained = false
	if c.classID == Rules.CLASS_ARMOR then
		if c.usable == false then return { score = 0, why = "unusable" } end
		typeScore = Rules.ArmorScore(player.class, player.level, c.subclassID, c.equipLoc)
		if not (Rules.NEUTRAL_SLOTS[c.equipLoc or ""] or c.subclassID == Rules.ARMOR.GENERIC) then
			typeName = Rules.ArmorName(c.subclassID)
		end
	elseif Rules.IsWeapon(c.classID, c.subclassID) then
		typeScore = Rules.WeaponScore(player.class, c.subclassID)
		typeName = Rules.WeaponName(c.subclassID)
		local trained = Rules.HasWeaponSkill(c.subclassID)
		if typeScore > 0 and (c.usable == false or trained == false) then
			untrained = true
			if settings and settings.weaponProficiency == "usable" then
				return { score = 0, why = "untrained", typeScore = typeScore, typeName = typeName, untrained = true }
			end
		end
	else
		return { score = 0, why = "notgear" }
	end
	if typeScore <= 0 then return { score = 0, why = "cannotwear", typeName = typeName } end
	local statScore, parts = 0, {}
	local weaponSubclass = Rules.IsWeapon(c.classID, c.subclassID) and c.subclassID or nil
	for key, amount in pairs(c.stats) do
		local weight = Rewards.WeightFor(player, key, weaponSubclass)
		if weight ~= 0 and amount ~= 0 then
			statScore = statScore + weight * amount
			parts[#parts + 1] = { key = key, amount = amount, value = weight * amount }
		end
	end
	table.sort(parts, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.key < b.key
	end)
	return { score = typeScore * (1 + statScore), typeScore = typeScore, statScore = statScore, parts = parts, typeName = typeName, untrained = untrained or nil }
end

--------------------------------------------------------------------------------
-- Stat value: the weighted sum of an item's stats for the player's class, in
-- "stat points" (Rules.WEIGHTS). A stat the class has no weight for counts
-- nothing, so cloth boots with spell damage are worth 0 to a hunter. Weapons add
-- DPS and attack speed at the class's melee or ranged weight (Rules.WeaponWeight,
-- picked by the weapon's kind); speed weights may be negative (slower is better).
--------------------------------------------------------------------------------
-- Pseudo-stats that are resolved per weapon kind rather than read straight from WEIGHTS.
Rewards.WEAPON_STAT_KEYS = { DAMAGE_PER_SECOND = "DPS", ATTACK_SPEED = "SPEED" }

local function WeightFor(player, key, weaponSubclass)
	local kindKey = Rewards.WEAPON_STAT_KEYS[key]
	if kindKey then
		if not weaponSubclass then return 0 end
		return Rules.WeaponWeight(player, weaponSubclass, kindKey)
	end
	return player.weights[key] or 0
end
Rewards.WeightFor = WeightFor

function Rewards.StatValue(stats, player, weaponSubclass)
	local total = 0
	for key, amount in pairs(stats or {}) do
		local weight = WeightFor(player, key, weaponSubclass)
		if weight ~= 0 and amount then total = total + weight * amount end
	end
	return total
end

-- Equipment slots for each INVTYPE; paired slots (rings, trinkets) compare with the
-- weaker of the two. One-hand weapons compare with the main hand.
Rewards.SLOTS = {
	INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3},
	INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6},
	INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9}, INVTYPE_HAND = {10},
	INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14}, INVTYPE_CLOAK = {15},
	INVTYPE_WEAPON = {16}, INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_2HWEAPON = {16},
	INVTYPE_WEAPONOFFHAND = {17}, INVTYPE_HOLDABLE = {17}, INVTYPE_SHIELD = {17},
	INVTYPE_RANGED = {18}, INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18},
}

-- Stats of a worn item: C_Item.GetItemStats, else the tooltip.
function Rewards.WornItemStats(link)
	if not link then return {} end
	local stats = Rewards.StatsFromAPI(link)
	local fromTooltip = Rewards.StatsFromTooltipData(NS.Call("C_TooltipInfo.GetHyperlink", link)) or {}
	if not stats then return fromTooltip end
	for _, key in ipairs(Rules.EXTRA_KEYS) do
		if stats[key] == nil and fromTooltip[key] then stats[key] = fromTooltip[key] end
	end
	return stats
end

-- The item worn where `equipLoc` goes: { link, itemLevel, slotID, value, stats, empty }.
-- nil when the slot is unknown or the worn item's data has not loaded (unknown is
-- not an empty slot), or when the inventory cannot be read at all. An empty slot
-- is { empty = true, value = 0 }.
function Rewards.WornItem(equipLoc, player)
	local okInv, hasInv = pcall(function() return type(GetInventoryItemLink) == "function" end)
	if not okInv or not hasInv then return nil end
	local worn
	for _, slotID in ipairs(Rewards.SLOTS[equipLoc or ""] or {}) do
		local link = NS.SafeString(NS.Call("GetInventoryItemLink", "player", slotID))
		local entry = { slotID = slotID, itemLevel = 0, value = 0, stats = {}, empty = link == nil }
		if link then
			local _, _, _, level = NS.Call("C_Item.GetItemInfo", link)
			if type(level) ~= "number" then return nil end
			local _, _, _, _, _, classID, subclassID = NS.Call("C_Item.GetItemInfoInstant", link)
			entry.link, entry.itemLevel = link, level
			entry.stats = Rewards.WornItemStats(link)
			local wornSubclass = Rules.IsWeapon(NS.SafeNumber(classID), NS.SafeNumber(subclassID)) and NS.SafeNumber(subclassID) or nil
			entry.value = player and Rewards.StatValue(entry.stats, player, wornSubclass) or 0
		end
		if not worn or entry.value < worn.value then worn = entry end
	end
	return worn
end

local function Value(c)
	return (c.sellPrice or 0) * (c.count or 1)
end
Rewards.VendorValue = Value

-- a beats b: fit score, then vendor value, then quality, then item level, then the earlier slot.
function Rewards.Better(a, b)
	local fa, fb = a.fit and a.fit.score or 0, b.fit and b.fit.score or 0
	if fa ~= fb then return fa > fb end
	if Value(a) ~= Value(b) then return Value(a) > Value(b) end
	if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
	if (a.itemLevel or 0) ~= (b.itemLevel or 0) then return (a.itemLevel or 0) > (b.itemLevel or 0) end
	return a.index < b.index
end

function Rewards.ByValue(items, reason)
	local best
	for _, c in ipairs(items) do
		c.value = Value(c)
		if c.value > 0 then
			if not best or c.value > best.value
				or (c.value == best.value and ((c.quality or 0) > (best.quality or 0)
					or ((c.quality or 0) == (best.quality or 0) and (c.itemLevel or 0) > (best.itemLevel or 0)))) then
				best = c
			end
		end
	end
	if best then return { index = best.index, choice = best, reason = reason or "value" } end
	return { reason = "novalue" }
end

-- Kinds of reward the addon does not pick unless the matching setting allows it.
-- When at least one is among the choices, the whole choice is the player's.
-- Checked in this order.
Rewards.KINDS = {
	{ key = "weapons", reason = "weapon", Is = function(c) return Rules.IsWeapon(c.classID, c.subclassID) end },
	{ key = "trinkets", reason = "trinket", Is = function(c) return Rules.IsTrinket(c.equipLoc) end },
}

-- The rewards to score, or nil and the reason the choice is handed to the player.
-- A guarded kind (weapon / trinket with its setting off) hands off only when the
-- choice is AMBIGUOUS: some other choice is something the character could wear.
-- When everything else is unwearable (a druid offered a staff or mail leggings)
-- the guarded item is the only usable option and is scored like anything else.
function Rewards.ApplyKinds(items, settings, player)
	for _, kind in ipairs(Rewards.KINDS) do
		if not settings[kind.key] then
			local guarded = false
			for _, c in ipairs(items) do
				if kind.Is(c) then guarded = true break end
			end
			if guarded then
				for _, c in ipairs(items) do
					if not kind.Is(c) and (player == nil or Rewards.Wearable(c, player)) then return nil, kind.reason end
				end
			end
		end
	end
	return items
end

-- Could the character wear this at all (armour class / weapon skill), stats aside?
function Rewards.Wearable(c, player)
	if not player or c.usable == false then return false end
	if c.classID == Rules.CLASS_ARMOR then
		return Rules.ArmorScore(player.class, player.level, c.subclassID, c.equipLoc) > 0
	elseif Rules.IsWeapon(c.classID, c.subclassID) then
		return Rules.WeaponScore(player.class, c.subclassID) > 0
	end
	return false
end

-- Decision: { index, choice, reason } when the addon picks, { reason } when the
-- choice is left to the player, { pending = true } while item data is missing.
function Rewards.Evaluate(choices, settings, player)
	if settings.rewardMode == "manual" then return { reason = "manual" } end
	local items = {}
	for _, c in ipairs(choices) do
		if c.lootType == Rewards.LOOT_ITEM then items[#items + 1] = c end
	end
	if #items == 0 then return { reason = "currency" } end
	for _, c in ipairs(items) do
		if not c.loaded then return { pending = true } end
	end
	-- A reward at or above the manual-quality threshold is the player's call.
	local threshold = tonumber(settings.manualQuality)
	if threshold and threshold >= 0 then
		local notable
		for _, c in ipairs(items) do
			if (c.quality or 0) >= threshold and (not notable or (c.quality or 0) > (notable.quality or 0)) then notable = c end
		end
		if notable then return { reason = "quality", choice = notable, quality = notable.quality } end
	end
	-- Weapons and trinkets are the player's call unless allowed, in either mode.
	local pool, handOff = Rewards.ApplyKinds(items, settings, player)
	if not pool then return { reason = handOff } end
	if settings.rewardMode == "value" then return Rewards.ByValue(pool, "value") end

	for _, c in ipairs(pool) do
		c.fit = Rewards.FitScore(c, player, settings)
		-- Stat value vs the worn item. A wearable reward worth no more than what the
		-- character already wears in that slot is not an upgrade: it keeps its
		-- wearability (for the weapon/trinket guards) but is treated as vendor
		-- value only, so zero-stat boots cannot beat a real upgrade.
		if c.fit.score > 0 then
			local weaponSubclass = Rules.IsWeapon(c.classID, c.subclassID) and c.subclassID or nil
			c.statValue = Rewards.StatValue(c.stats, player, weaponSubclass)
			c.worn = Rewards.WornItem(c.equipLoc, player)
			if c.worn then
				c.wornValue = c.worn.value
				c.statGain = c.statValue - c.worn.value
			end
			c.upgrade = c.statValue > 0 and (c.worn == nil or c.statGain > 0)
			if not c.upgrade then
				c.fit.sidelined = true
				c.fit.why = c.statValue > 0 and "notupgrade" or "nostats"
				c.fit.score = 0
			else
				-- Rank upgrades by how much they add; typeScore keeps lighter armour behind.
				c.fit.score = c.fit.typeScore * (1 + (c.statGain or c.statValue))
			end
		end
	end

	-- Weapon kind. The best weapon of the kind the class wants (ranged for a hunter, melee
	-- for the melee classes) beats every weapon of the other kind, however they score.
	-- Between that weapon and the rest (armour, rings...) the score decides. A weapon of
	-- the other kind keeps its score: it competes with the rest as usual, wins outright when
	-- no wanted-kind weapon is offered, and when it beats the rest it is the wanted weapon,
	-- not the rest, that is taken.
	local wanted
	if settings.weapons and player.weaponKind then
		for _, c in ipairs(pool) do
			if c.fit.score > 0 and Rules.IsWeapon(c.classID, c.subclassID)
				and Rules.WeaponCategory(c.subclassID) == player.weaponKind
				and (not wanted or Rewards.Better(c, wanted)) then
				wanted = c
			end
		end
	end

	local best
	if wanted then
		local other
		for _, c in ipairs(pool) do
			if c ~= wanted and c.fit.score > 0 then
				if Rules.IsWeapon(c.classID, c.subclassID) and Rules.WeaponCategory(c.subclassID) ~= player.weaponKind then
					c.fit.otherKind = true
				end
				if not other or Rewards.Better(c, other) then other = c end
			end
		end
		if not other or Rules.IsWeapon(other.classID, other.subclassID) then
			best = wanted
		else
			best = Rewards.Better(wanted, other) and wanted or other
		end
	else
		for _, c in ipairs(pool) do
			if c.fit.score > 0 and (not best or Rewards.Better(c, best)) then best = c end
		end
	end
	if best then return { index = best.index, choice = best, reason = "fit", pool = pool } end
	if settings.fallbackToValue then
		-- Nothing is an upgrade: take the most valuable, but never a thing the class can
		-- never equip while something wearable is offered (a gun for a druid). Only when
		-- nothing at all is wearable is gold the whole story.
		local wearable = {}
		for _, c in ipairs(pool) do
			if Rewards.Wearable(c, player) or (c.fit and c.fit.untrained) then wearable[#wearable + 1] = c end
		end
		local decision = Rewards.ByValue(#wearable > 0 and wearable or pool, "fallback")
		if decision.index then
			decision.pool = pool
			return decision
		end
	end
	return { reason = "nofit", pool = pool }
end

--------------------------------------------------------------------------------
-- Text.
--------------------------------------------------------------------------------
local function FormatAmount(amount)
	if amount == math.floor(amount) then return format("%+d", amount) end
	return format("%+.1f", amount)
end
Rewards.FormatAmount = FormatAmount

function Rewards.Describe(decision)
	local c = decision.choice
	if not c then return "" end
	if decision.reason == "prepick" then return L["your pre-pick"] end
	if decision.reason == "fit" then
		local bits = {}
		if c.fit and c.fit.typeName then bits[#bits + 1] = c.fit.typeName end
		for i = 1, math.min(3, c.fit and #c.fit.parts or 0) do
			local p = c.fit.parts[i]
			bits[#bits + 1] = FormatAmount(p.amount) .. " " .. Rules.StatName(p.key)
		end
		if c.statGain and c.worn and not c.worn.empty then
			bits[#bits + 1] = format(L["%s over what you wear"], FormatAmount(c.statGain))
		end
		if c.fit and c.fit.untrained then bits[#bits + 1] = L["needs weapon training"] end
		if #bits == 0 then bits[1] = L["usable by your class"] end
		return format(L["best fit: %s"], table.concat(bits, ", "))
	elseif decision.reason == "fallback" then
		return format(L["nothing fits, most valuable: %s"], NS.FormatMoney(c.value or Value(c)))
	end
	return format(L["most valuable: %s"], NS.FormatMoney(c.value or Value(c)))
end

function Rewards.ReasonText(reason, decision)
	if reason == "manual" then return L["reward choice is set to manual"] end
	if reason == "quality" then
		return format(L["a %s reward is offered"], NS.QualityName(decision and decision.quality or 0))
	end
	if reason == "weapon" then return L["a weapon is offered"] end
	if reason == "trinket" then return L["a trinket is offered"] end
	if reason == "nofit" then return L["none of the rewards fits your class"] end
	if reason == "notupgrade" then return L["no reward beats what you wear"] end
	if reason == "nostats" then return L["no reward has stats your class wants"] end
	if reason == "novalue" then return L["the rewards have no vendor value"] end
	if reason == "currency" then return L["only currencies are offered"] end
	if reason == "pending" then return L["the item data did not load in time"] end
	return tostring(reason)
end

function Rewards.ChoiceLabel(c)
	return c.link or c.name or (c.itemID and ("item:" .. c.itemID)) or "?"
end
