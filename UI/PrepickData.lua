-- Read-only data for the retained pre-pick UI. Nothing in the original runtime
-- calls this module. In particular it does not decide quest eligibility, handle
-- NPC events, override Rewards.Evaluate, or apply saved picks at hand-in.
local ADDON, NS = ...
local Rewards, Rules, L = NS.Rewards, NS.Rules, NS.L
local Data = {}
NS.PrePickData = Data

local function Pack(...) return { n = select("#", ...), ... } end

function Data.ListQuests()
	local quests = {}
	if C_QuestLog and C_QuestLog.GetInfo then
		local count = NS.SafeNumber(NS.Call("C_QuestLog.GetNumQuestLogEntries")) or 0
		for questLogIndex = 1, count do
			local row = NS.Call("C_QuestLog.GetInfo", questLogIndex)
			if row and not row.isHeader and not row.isHidden and not row.isTask and row.questID and row.questID > 0 then
				quests[#quests + 1] = { questID = row.questID, title = row.title }
			end
		end
	else
		local count = NS.SafeNumber(NS.Call("GetNumQuestLogEntries")) or 0
		for questLogIndex = 1, count do
			local title, _, _, isHeader, _, _, _, questID = NS.Call("GetQuestLogTitle", questLogIndex)
			if not isHeader and type(questID) == "number" and questID > 0 then
				quests[#quests + 1] = { questID = questID, title = title }
			end
		end
	end
	return quests
end

function Data.QuestTitle(questID)
	for _, quest in ipairs(Data.ListQuests()) do
		if quest.questID == questID then return quest.title end
	end
end

function Data.SelectedQuestID()
	if C_QuestLog and C_QuestLog.GetSelectedQuest then
		return NS.SafeNumber(NS.Call("C_QuestLog.GetSelectedQuest"))
	end
	return NS.SafeNumber(NS.Call("GetQuestLogSelectedID"))
end

-- Snapshot legacy log choices while the requested quest is selected, then
-- immediately restore the old selection (including 0). The resulting source
-- never reads the changing global selection again. Modern APIs take questID.
function Data.LogSource(questID)
	local choices = {}
	local function ReadChoices(legacy)
		local apiQuestID
		if not legacy then apiQuestID = questID end
		local count = NS.SafeNumber(NS.Call("GetNumQuestLogChoices", apiQuestID)) or 0
		for rewardChoiceIndex = 1, count do
			local info = Pack(NS.Call("GetQuestLogChoiceInfo", rewardChoiceIndex, apiQuestID))
			local link
			if legacy then link = NS.SafeString(NS.Call("GetQuestLogItemLink", "choice", rewardChoiceIndex)) end
			local itemID = NS.SafeNumber(info[6]) or (link and tonumber(link:match("item:(%d+)")))
			if itemID and not link then
				local _, itemLink = NS.Call("C_Item.GetItemInfo", itemID)
				link = NS.SafeString(itemLink) or ("item:" .. itemID)
			end
			info[6], info.n = itemID, 6
			choices[rewardChoiceIndex] = { info = info, link = link, itemID = itemID }
		end
	end
	if C_QuestLog and C_QuestLog.GetSelectedQuest then
		ReadChoices(false)
	else
		local questLogIndex = NS.SafeNumber(NS.Call("GetQuestLogIndexByID", questID))
		local previousIndex = NS.SafeNumber(NS.Call("GetQuestLogSelection"))
		if questLogIndex and questLogIndex > 0 and previousIndex ~= nil then
			if previousIndex ~= questLogIndex then NS.Call("SelectQuestLogEntry", questLogIndex) end
			local ok, err = pcall(ReadChoices, true)
			if previousIndex ~= questLogIndex then NS.Call("SelectQuestLogEntry", previousIndex) end
			if not ok then error(err) end
		end
	end
	return {
		name = "ui-log", questID = questID,
		Count = function() return #choices end,
		LootType = function() return Rewards.LOOT_ITEM end,
		Info = function(rewardChoiceIndex) local info = choices[rewardChoiceIndex].info; return unpack(info, 1, info.n) end,
		Link = function(rewardChoiceIndex) return choices[rewardChoiceIndex].link end,
		Tooltip = function(rewardChoiceIndex)
			local choice = choices[rewardChoiceIndex]
			if choice.link then return NS.Call("C_TooltipInfo.GetHyperlink", choice.link) end
		end,
	}
end

function Data.ItemListSource(itemIDs)
	return {
		name = "ui-samples",
		Count = function() return #itemIDs end,
		LootType = function() return Rewards.LOOT_ITEM end,
		Info = function(rewardChoiceIndex)
			local itemID = itemIDs[rewardChoiceIndex]
			local name, _, quality = NS.Call("C_Item.GetItemInfo", itemID)
			return name, nil, 1, quality, true, itemID
		end,
		Link = function(rewardChoiceIndex) return "item:" .. itemIDs[rewardChoiceIndex] end,
		Tooltip = function(rewardChoiceIndex) return NS.Call("C_TooltipInfo.GetHyperlink", "item:" .. itemIDs[rewardChoiceIndex]) end,
	}
end

function Data.ItemStats(link)
	if not link then return nil end
	local stats = Rewards.StatsFromAPI(link)
	if stats then return stats end
	if type(GetItemStats) == "function" then
		local raw = NS.Call("GetItemStats", link)
		if type(raw) == "table" then
			local normalized = {}
			for key, value in pairs(raw) do
				local stat = key:match("^ITEM_MOD_(.+)_SHORT$") or key:match("^ITEM_MOD_(.+)$")
				if key == "RESISTANCE0_NAME" then stat = "ARMOR" end
				if stat and type(value) == "number" then normalized[stat] = value end
			end
			if next(normalized) then return normalized end
		end
	end
	return Rewards.StatsFromTooltipData(NS.Call("C_TooltipInfo.GetHyperlink", link))
end

-- Display comparison only. One-hand weapons compare with main hand, rather
-- than treating an empty offhand as an upgrade. Paired jewellery uses the lower
-- item level. These facts never feed the original automation's decision.
local SLOTS = {
	INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3},
	INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6},
	INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9}, INVTYPE_HAND = {10},
	INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14}, INVTYPE_CLOAK = {15},
	INVTYPE_WEAPON = {16}, INVTYPE_WEAPONMAINHAND = {16}, INVTYPE_2HWEAPON = {16},
	INVTYPE_WEAPONOFFHAND = {17}, INVTYPE_HOLDABLE = {17}, INVTYPE_SHIELD = {17},
	INVTYPE_RANGED = {18}, INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18},
}
local function WornItem(equipLoc)
	local worn
	for _, slotID in ipairs(SLOTS[equipLoc or ""] or {}) do
		local link = NS.SafeString(NS.Call("GetInventoryItemLink", "player", slotID))
		local itemLevel = 0
		if link then
			local _, _, _, level = NS.Call("C_Item.GetItemInfo", link)
			if type(level) ~= "number" then return nil end -- unknown is not an empty slot
			itemLevel = level
		end
		if not worn or itemLevel < worn.itemLevel then worn = { link = link, itemLevel = itemLevel, slotID = slotID } end
	end
	return worn
end

-- Translate the ORIGINAL decision shape for display, not for automation.
-- When it declines to pick, a fit-based suggestion may still be highlighted.
function Data.Evaluate(choices, settings, player, questID)
	local resolved = NS.TurnInResolver.Resolve({
		questID = questID, rewardChoiceCount = #choices, rewardChoices = choices,
		settings = settings, player = player,
	})
	for _, choice in ipairs(choices) do
		if choice.loaded == false then return { pending = true, reason = "pending", prePickStatus = resolved.prePickStatus } end
	end
	local original = resolved.rewardDecision or { reason = resolved.reason, pending = resolved.action == "wait" }
	if original.pending then return { pending = true, reason = "pending", prePickStatus = resolved.prePickStatus } end
	local suggested = original.choice
	for _, choice in ipairs(choices) do
		if choice.lootType == Rewards.LOOT_ITEM then
			choice.fit = Rewards.FitScore(choice, player)
			choice.wearable = (choice.fit.typeScore or 0) > 0
			choice.worn = choice.wearable and WornItem(choice.equipLoc) or nil
			if not original.choice and (not suggested or Rewards.Better(choice, suggested)) then suggested = choice end
		end
	end
	return {
		pending = original.pending, action = resolved.action == "submit" and "auto" or "recommend",
		index = suggested and suggested.index, choice = suggested, original = original,
		reason = original.reason,
		prePickStatus = resolved.prePickStatus,
	}
end

function Data.DecisionText(decision)
	if not decision or decision.pending then return L["item data not loaded"] end
	local original = decision.original or decision
	if decision.prePickStatus == "unavailable" or decision.prePickStatus == "ambiguous" then
		return L["Saved reward cannot be matched; original reward rules apply."]
	end
	if original.index then return Rewards.Describe(original) end
	return Rewards.ReasonText(original.reason, original)
end

function Data.ItemText(choice)
	if choice.loaded == false then return L["item data not loaded"] end
	if choice.wearable then return L["wearable"] end
	return L["cannot wear"]
end