-- QuestAutomator: the reward priority engine (spec §6). Decides, for a set of
-- reward choices, which one the addon favours and whether it may click it.
--
-- Tiers, first match wins:
--   P  a pre-pick the player made at accept time (itemID)        -> auto
--   Q  a reward of manualQuality or better is offered             -> recommend
--   1  a hard-to-value reward: trinket, relic, Use/proc, not gear -> tier1Action
--   2  exactly one best-wearable reward is a clear upgrade         -> tier2Action
--   3  exactly one best-wearable reward is a sidegrade             -> tier3Action
--   4  two or more rewards are upgrades or sidegrades              -> tier4Action
--   5  nothing wearable: the most valuable reward                  -> tier5Action
-- Every tier action is "auto" (take it) or "recommend" (glow it, leave the window
-- open). The engine always names an index to glow; the action says whether to click.
--
-- "Best-wearable" is Rules.IsBestWearable: the class's best armour class at this
-- level, neutral slots, shields / relics for their classes, weapons the class can
-- train (or has the skill for, by settings.weaponProficiency). Lighter armour is not
-- wearable here (spec §6.2). "Upgrade" and "sidegrade" compare the reward's item
-- level to the weakest piece in the slot it would fill (Client.WornItemLevel) with
-- settings.ilvlBand (default 2): delta > band = upgrade, |delta| <= band = sidegrade.
-- Class stat weights (Rewards.FitScore) only break ties inside a tier.
local ADDON, NS = ...
local L = NS.L
local Rules, Rewards = NS.Rules, NS.Rewards
local Engine = {}
NS.Engine = Engine

Engine.TIERS = { "P", "Q", "1", "2", "3", "4", "5" }
Engine.TIER_SETTING = { ["1"] = "tier1Action", ["2"] = "tier2Action", ["3"] = "tier3Action", ["4"] = "tier4Action", ["5"] = "tier5Action" }
Engine.ACTIONS = { "recommend", "auto" }
Engine.DEFAULT_BAND = 2

--------------------------------------------------------------------------------
-- Per-item facts the tiers need. Writes onto each choice:
--   wearable, wearReason        Rules.IsBestWearable
--   hardToValue, hardReason     Rules.IsHardToValue
--   worn = { itemLevel, slotID, link } | nil   the piece it would replace
--   delta                       itemLevel - worn.itemLevel, nil when not comparable
--   isUpgrade, isSidegrade      by settings.ilvlBand
--   otherKind                   a weapon of the kind the class does not want
--   value, valueSource          Client.ItemValue (settings.valueSource)
--   fit                         Rewards.FitScore (tie-break only)
--------------------------------------------------------------------------------
function Engine.Classify(items, player, settings)
	local band = tonumber(settings.ilvlBand) or Engine.DEFAULT_BAND
	for _, c in ipairs(items) do
		c.wearable, c.wearReason = Rules.IsBestWearable(c, player, settings)
		c.hardToValue, c.hardReason = Rules.IsHardToValue(c)
		c.worn = c.wearable and NS.Client.WornItemLevel(c.equipLoc) or nil
		c.delta = c.worn and ((c.itemLevel or 0) - c.worn.itemLevel) or nil
		c.isUpgrade = c.delta ~= nil and c.delta > band
		c.isSidegrade = c.delta ~= nil and c.delta >= -band and c.delta <= band
		c.otherKind = false
		if Rules.IsWeapon(c.classID, c.subclassID) and player.weaponKind then
			c.otherKind = Rules.WeaponCategory(c.subclassID) ~= player.weaponKind
		end
		c.value, c.valueSource = NS.Client.ItemValue(c.link, c.count, c.sellPrice, settings.valueSource)
		c.fit = Rewards.FitScore(c, player)
	end
	return items
end

-- a beats b inside one tier: bigger item-level gain, then the class weight score,
-- then value, then quality, then the earlier slot.
function Engine.BetterUpgrade(a, b)
	if (a.delta or -math.huge) ~= (b.delta or -math.huge) then return (a.delta or -math.huge) > (b.delta or -math.huge) end
	local fa, fb = a.fit and a.fit.score or 0, b.fit and b.fit.score or 0
	if fa ~= fb then return fa > fb end
	if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
	if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
	return a.index < b.index
end

function Engine.ActionFor(settings, tier)
	local key = Engine.TIER_SETTING[tier]
	local action = key and settings[key] or "recommend"
	if action ~= "auto" then action = "recommend" end
	return action
end

local function Decision(tier, action, choice, pool, extra)
	local d = { tier = tier, action = action, index = choice and choice.index or nil, choice = choice, pool = pool }
	if extra then for k, v in pairs(extra) do d[k] = v end end
	return d
end

-- The best wearable choice by upgrade order (for the glow when a tier hands off).
function Engine.BestCandidate(items)
	local best
	for _, c in ipairs(items) do
		if c.wearable and not c.otherKind and (not best or Engine.BetterUpgrade(c, best)) then best = c end
	end
	return best
end

--------------------------------------------------------------------------------
-- RewardDecision (spec §6.3):
--   { tier, action = "auto"|"recommend", index, choice, pool, reason, ... }
--   { pending = true }          while item data is still loading
--   { reason = "currency" }     no item among the choices
-- settings.prePickItemID (set by the pre-pick UI for the quest being handed in)
-- decides outright.
--------------------------------------------------------------------------------
function Engine.Evaluate(choices, settings, player)
	local items = {}
	for _, c in ipairs(choices) do
		if c.lootType == Rewards.LOOT_ITEM then items[#items + 1] = c end
	end
	if #items == 0 then return { reason = "currency" } end
	for _, c in ipairs(items) do
		if not c.loaded then return { pending = true } end
	end
	Engine.Classify(items, player, settings)

	-- P: a pre-pick made at accept time, keyed by itemID so reordering cannot misfire.
	local prePick = settings.prePickItemID
	if prePick then
		for _, c in ipairs(items) do
			if c.itemID == prePick then return Decision("P", "auto", c, items, { reason = "prepick" }) end
		end
	end

	-- Q: a reward at or above the manual-quality threshold is the player's call.
	local threshold = tonumber(settings.manualQuality)
	if threshold and threshold >= 0 then
		local notable
		for _, c in ipairs(items) do
			if (c.quality or 0) >= threshold and (not notable or (c.quality or 0) > (notable.quality or 0)) then notable = c end
		end
		if notable then
			return Decision("Q", "recommend", Engine.BestCandidate(items) or notable, items, { reason = "quality", quality = notable.quality, notable = notable })
		end
	end

	-- 1: anything hard to value hands the whole choice over; glow the best wearable guess.
	local hard
	for _, c in ipairs(items) do
		if c.hardToValue and (not hard or Engine.BetterUpgrade(c, hard)) then hard = c end
	end
	if hard then
		return Decision("1", Engine.ActionFor(settings, "1"), Engine.BestCandidate(items) or hard, items, { reason = hard.hardReason, hard = hard })
	end

	-- 2 / 3 / 4: upgrades and sidegrades among the best-wearable rewards of the wanted weapon kind.
	local candidates = {}
	for _, c in ipairs(items) do
		if c.wearable and not c.otherKind and (c.isUpgrade or c.isSidegrade) then candidates[#candidates + 1] = c end
	end
	table.sort(candidates, Engine.BetterUpgrade)
	if #candidates >= 2 then
		return Decision("4", Engine.ActionFor(settings, "4"), candidates[1], items, { reason = "competing", candidates = candidates })
	end
	if #candidates == 1 then
		local c = candidates[1]
		if c.isUpgrade then return Decision("2", Engine.ActionFor(settings, "2"), c, items, { reason = "upgrade" }) end
		return Decision("3", Engine.ActionFor(settings, "3"), c, items, { reason = "sidegrade" })
	end

	-- 5: nothing wearable, or every wearable piece is a downgrade: the most valuable.
	local best
	for _, c in ipairs(items) do
		if (c.value or 0) > 0 and (not best or (c.value > best.value)
			or (c.value == best.value and ((c.quality or 0) > (best.quality or 0)
				or ((c.quality or 0) == (best.quality or 0) and (c.itemLevel or 0) > (best.itemLevel or 0))))) then
			best = c
		end
	end
	if best then return Decision("5", Engine.ActionFor(settings, "5"), best, items, { reason = "value" }) end
	-- Nothing has a value either: glow the first item, never click.
	return Decision("5", "recommend", items[1], items, { reason = "novalue" })
end

--------------------------------------------------------------------------------
-- Text for chat lines and /qam why.
--------------------------------------------------------------------------------
function Engine.TierName(tier)
	if tier == "P" then return L["your pre-pick"] end
	if tier == "Q" then return L["rare or better"] end
	if tier == "1" then return L["hard to value"] end
	if tier == "2" then return L["upgrade"] end
	if tier == "3" then return L["sidegrade"] end
	if tier == "4" then return L["several upgrades"] end
	if tier == "5" then return L["most valuable"] end
	return tostring(tier)
end

-- One line describing why the engine favours decision.choice.
function Engine.Describe(decision)
	local c = decision.choice
	if not c then return "" end
	local tier = decision.tier
	if tier == "P" then return L["the reward you picked when you took the quest"] end
	if tier == "2" or tier == "3" or tier == "4" then
		local worn = c.worn and c.worn.itemLevel or 0
		local slotName = c.equipLoc and _G[c.equipLoc] or "?"
		return string.format(L["item level %d vs %d worn in %s (%+d)"], c.itemLevel or 0, worn, tostring(slotName), c.delta or 0)
	end
	if tier == "5" then return string.format(L["most valuable: %s"], NS.FormatMoney(c.value or 0)) end
	if tier == "Q" then return string.format(L["a %s reward is offered"], NS.QualityName(decision.quality or 0)) end
	if tier == "1" then return Engine.HardReasonText(decision.reason) end
	return tostring(decision.reason)
end

function Engine.HardReasonText(reason)
	if reason == "trinket" then return L["a trinket is offered"] end
	if reason == "relic" then return L["a relic is offered"] end
	if reason == "use" then return L["a reward has a Use effect"] end
	if reason == "proc" then return L["a reward has a chance-on-hit effect"] end
	if reason == "equipeffect" then return L["a reward has an Equip effect the addon cannot value"] end
	if reason == "notgear" then return L["a reward is not equipment"] end
	return tostring(reason)
end

-- Why the window was left open (decision.action == "recommend").
function Engine.LeaveReasonText(decision)
	if not decision then return "?" end
	if decision.reason == "currency" then return L["only currencies are offered"] end
	if decision.reason == "novalue" then return L["nothing is wearable and nothing has a vendor value"] end
	if decision.tier == "Q" then return Engine.Describe(decision) end
	if decision.tier == "1" then return Engine.HardReasonText(decision.reason) end
	if decision.tier == "4" then return string.format(L["%d rewards are upgrades or sidegrades"], #(decision.candidates or {})) end
	return string.format(L["%s is set to recommend only"], Engine.TierName(decision.tier))
end

-- Why one item is where it is, for /qam why.
function Engine.ItemReasonText(c)
	local bits = {}
	if c.hardToValue then bits[#bits + 1] = Engine.HardReasonText(c.hardReason) end
	if c.wearable then
		if c.worn then
			bits[#bits + 1] = string.format(L["ilvl %d, worn %d (%+d)"], c.itemLevel or 0, c.worn.itemLevel, c.delta or 0)
			if c.isUpgrade then bits[#bits + 1] = L["upgrade"]
			elseif c.isSidegrade then bits[#bits + 1] = L["sidegrade"]
			else bits[#bits + 1] = L["downgrade"] end
		else
			bits[#bits + 1] = L["wearable"]
		end
		if c.otherKind then bits[#bits + 1] = L["not the preferred weapon kind"] end
	else
		local r = c.wearReason
		if r == "lighter" then bits[#bits + 1] = L["lighter than your armour class"]
		elseif r == "heavier" then bits[#bits + 1] = L["heavier than your armour class"]
		elseif r == "cannotlearn" then bits[#bits + 1] = L["your class cannot learn this weapon"]
		elseif r == "noskill" then bits[#bits + 1] = L["you have not trained this weapon"]
		elseif r == "notgear" then bits[#bits + 1] = L["not equipment"]
		elseif r == "unusable" then bits[#bits + 1] = L["cannot use"]
		else bits[#bits + 1] = L["cannot wear"] end
	end
	if c.fit and c.fit.score > 0 then bits[#bits + 1] = string.format(L["score %.1f"], c.fit.score) end
	return table.concat(bits, " | ")
end