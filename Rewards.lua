-- QuestAutomator: reading the reward choices of the open quest and
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
function Rewards.LogSource(questID)
	return {
		name = "log",
		questID = questID,
		Count = function() return NS.Client.LogChoiceCount(questID) end,
		LootType = function() return Rewards.LOOT_ITEM end,
		Info = function(i) return NS.Client.LogChoiceInfo(i, questID) end,
		Link = function(i) return NS.Call("GetQuestLogItemLink", "choice", i) end,
		Tooltip = function(i) return NS.Client.LogChoiceTooltip(i, questID) end,
	}
end

-- Format strings for the tooltip parser live in the client adapter
-- (NS.Client.StatFormats(): Forever's rating strings, Era's vanilla ones).

-- Tag -> stat key for the pseudo-stats.
Rewards.TEMPLATE_KEYS = { DPS_TEMPLATE = "DAMAGE_PER_SECOND", ARMOR_TEMPLATE = "ARMOR" }

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
			if fmt:sub(i, i + 1) == "%%" then
				out[#out + 1] = "%%"
				i = i + 2
			else
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
	local formats = NS.Client.StatFormats()
	for _, fmt in ipairs(formats[tag] or {}) do
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
	return NS.Client.ItemStats(link)
end

function Rewards.StatsFromTooltip(index, kind)
	return Rewards.StatsFromTooltipData(NS.Call("C_TooltipInfo.GetQuestItem", kind or "choice", index))
end

function Rewards.StatsFromTooltipData(data)
	if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	local stats, any = {}, false
	for _, line in ipairs(data.lines) do
		local text = type(line) == "table" and NS.SafeString(line.leftText) or nil
		if text then
			local key, value = Rewards.ParseStatLine(text)
			if key then
				stats[key] = (stats[key] or 0) + value
				any = true
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
				local stats = Rewards.StatsFromAPI(c.link)
				c.statsSource = stats and "api" or nil
				if not stats then
					stats = Rewards.StatsFromTooltipData(source.Tooltip(i))
					c.statsSource = stats and "tooltip" or "none"
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
function Rewards.FitScore(c, player)
	if c.usable == false then return { score = 0, why = "unusable" } end
	local typeScore, typeName
	if c.classID == Rules.CLASS_ARMOR then
		typeScore = Rules.ArmorScore(player.class, player.level, c.subclassID, c.equipLoc)
		if not (Rules.NEUTRAL_SLOTS[c.equipLoc or ""] or c.subclassID == Rules.ARMOR.GENERIC) then
			typeName = Rules.ArmorName(c.subclassID)
		end
	elseif Rules.IsWeapon(c.classID, c.subclassID) then
		typeScore = Rules.WeaponScore(player.class, c.subclassID)
		typeName = Rules.WeaponName(c.subclassID)
	else
		return { score = 0, why = "notgear" }
	end
	if typeScore <= 0 then return { score = 0, why = "cannotwear", typeName = typeName } end
	local statScore, parts = 0, {}
	for key, amount in pairs(c.stats) do
		local weight = player.weights[key] or 0
		if key == "DAMAGE_PER_SECOND" and Rules.IsWeapon(c.classID, c.subclassID) then weight = Rules.DPS_WEIGHT end
		if weight > 0 and amount ~= 0 then
			statScore = statScore + weight * amount
			parts[#parts + 1] = { key = key, amount = amount, value = weight * amount }
		end
	end
	table.sort(parts, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.key < b.key
	end)
	return { score = typeScore * (1 + statScore), typeScore = typeScore, statScore = statScore, parts = parts, typeName = typeName }
end

local function Value(c)
	return (c.sellPrice or 0) * (c.count or 1)
end

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
function Rewards.ApplyKinds(items, settings)
	for _, kind in ipairs(Rewards.KINDS) do
		if not settings[kind.key] then
			for _, c in ipairs(items) do
				if kind.Is(c) then return nil, kind.reason end
			end
		end
	end
	return items
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
	local pool, handOff = Rewards.ApplyKinds(items, settings)
	if not pool then return { reason = handOff } end
	if settings.rewardMode == "value" then return Rewards.ByValue(pool, "value") end

	for _, c in ipairs(pool) do
		c.fit = Rewards.FitScore(c, player)
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
		local decision = Rewards.ByValue(pool, "fallback")
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
	if decision.reason == "fit" then
		local bits = {}
		if c.fit and c.fit.typeName then bits[#bits + 1] = c.fit.typeName end
		for i = 1, math.min(3, c.fit and #c.fit.parts or 0) do
			local p = c.fit.parts[i]
			bits[#bits + 1] = FormatAmount(p.amount) .. " " .. Rules.StatName(p.key)
		end
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
	if reason == "novalue" then return L["the rewards have no vendor value"] end
	if reason == "currency" then return L["only currencies are offered"] end
	if reason == "pending" then return L["the item data did not load in time"] end
	return tostring(reason)
end

function Rewards.ChoiceLabel(c)
	return c.link or c.name or (c.itemID and ("item:" .. c.itemID)) or "?"
end
