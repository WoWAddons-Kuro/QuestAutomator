-- Quest Automator: WoW Forever client (Mainline UI, interface 16001).
-- Implements the interface in Client/Client.lua. Ground truth: build 69893
-- QuestFrame.lua / GossipFrameShared.lua, QuestLogDocumentation.lua.
local ADDON, NS = ...
local Client = NS.Client

local Forever = {}
NS.ClientFlavours.forever = Forever

--------------------------------------------------------------------------------
-- Frequency encoding. Forever uses Enum.QuestFrequency EVERYWHERE (gossip tables,
-- GetAvailableQuestInfo, C_QuestLog). QuestLogDocumentation.lua:
--   Default = 0, Daily = 1, Weekly = 2, ResetByScheduler = 3
--------------------------------------------------------------------------------
local ENUM_FREQUENCY = {}
do
	local E = Enum and Enum.QuestFrequency or {}
	ENUM_FREQUENCY[E.Default or 0] = Client.FREQUENCY_DEFAULT
	ENUM_FREQUENCY[E.Daily or 1] = Client.FREQUENCY_DAILY
	ENUM_FREQUENCY[E.Weekly or 2] = Client.FREQUENCY_WEEKLY
	ENUM_FREQUENCY[E.ResetByScheduler or 3] = Client.FREQUENCY_SCHEDULED
end

--------------------------------------------------------------------------------
-- Interface.
--------------------------------------------------------------------------------
function Forever.GossipQuestInfo(info)
	return {
		questID = NS.SafeNumber(info.questID),
		title = NS.SafeString(info.title),
		isTrivial = NS.SafeBool(info.isTrivial),
		isRepeatable = NS.SafeBool(info.repeatable),
		isComplete = NS.SafeBool(info.isComplete),
		frequency = Client.DecodeFrequency(ENUM_FREQUENCY, info.frequency),
	}
end

-- GetAvailableQuestInfo(i) -> isTrivial, frequency(Enum), isRepeatable, isLegendary, questID, isImportant
function Forever.AvailableQuestInfo(index)
	local isTrivial, frequency, isRepeatable, _, questID = NS.Call("GetAvailableQuestInfo", index)
	return {
		questID = NS.SafeNumber(questID),
		isTrivial = NS.SafeBool(isTrivial),
		isRepeatable = NS.SafeBool(isRepeatable),
		frequency = Client.DecodeFrequency(ENUM_FREQUENCY, frequency),
		rawFrequency = frequency,
	}
end

function Forever.ActiveQuestID(index)
	return NS.SafeNumber(NS.Call("GetActiveQuestID", index))
end

function Forever.QuestTitle(questID)
	return NS.SafeString(NS.Call("C_QuestLog.GetTitleForQuestID", questID))
end

function Forever.IsQuestTrivial(questID)
	return questID ~= nil and NS.SafeBool(NS.Call("C_QuestLog.IsQuestTrivial", questID))
end

function Forever.IsQuestRepeatable(questID)
	return questID ~= nil and NS.SafeBool(NS.Call("C_QuestLog.IsRepeatableQuest", questID))
end

function Forever.IsQuestComplete(questID)
	if not questID then return false end
	if NS.SafeBool(NS.Call("C_QuestLog.IsOnQuest", questID)) then
		return NS.SafeBool(NS.Call("C_QuestLog.IsComplete", questID)) and not NS.SafeBool(NS.Call("C_QuestLog.IsFailed", questID))
	end
	-- The legacy global still exists on Forever (QuestFrame.lua); the log may lag a server-side accept.
	return NS.SafeBool(NS.Call("IsQuestComplete", questID))
end

-- C_QuestLog.GetInfo(i) -> table { questID, title, isHeader, isHidden, isTask, ... }
function Forever.QuestLogQuests()
	local list = {}
	local n = NS.SafeNumber(NS.Call("C_QuestLog.GetNumQuestLogEntries")) or 0
	for index = 1, n do
		local info = NS.Call("C_QuestLog.GetInfo", index)
		if type(info) == "table" and not NS.SafeBool(info.isHeader) and not NS.SafeBool(info.isHidden) and not NS.SafeBool(info.isTask) then
			local questID = NS.SafeNumber(info.questID)
			if questID and questID > 0 then
				list[#list + 1] = { questID = questID, title = NS.SafeString(info.title), isComplete = Forever.IsQuestComplete(questID) }
			end
		end
	end
	return list
end

function Forever.SelectedQuestLogQuestID()
	local id = NS.SafeNumber(NS.Call("C_QuestLog.GetSelectedQuest"))
	if id and id > 0 then return id end
	return nil
end

-- Forever's quest-log reward globals take questID (GetNumQuestLogChoices(questID),
-- GetQuestLogChoiceInfo(i, questID) -> name, texture, count, quality, isUsable, itemID).
function Forever.QuestLogChoiceSource(questID)
	local choices = {}
	local count = NS.SafeNumber(NS.Call("GetNumQuestLogChoices", questID)) or 0
	for i = 1, count do
		local name, texture, num, quality, isUsable, itemID = NS.Call("GetQuestLogChoiceInfo", i, questID)
		itemID = NS.SafeNumber(itemID)
		local link = NS.SafeString(NS.Call("GetQuestLogItemLink", "choice", i))
		if itemID and not link then
			local _, itemLink = NS.Call("C_Item.GetItemInfo", itemID)
			link = NS.SafeString(itemLink) or ("item:" .. itemID)
		end
		choices[i] = { info = { name, texture, num, quality, isUsable, itemID }, link = link, itemID = itemID }
	end
	return {
		name = "log", questID = questID,
		Count = function() return #choices end,
		Info = function(i) return unpack(choices[i].info, 1, 6) end,
		Link = function(i) return choices[i].link end,
		Tooltip = function(i) return NS.Call("C_TooltipInfo.GetQuestLogItem", "choice", i, questID) end,
	}
end

function Forever.QuestLogRewardXP(questID)
	return NS.SafeNumber(NS.Call("GetQuestLogRewardXP", questID)) or 0
end

function Forever.DebugReport()
	local E = Enum and Enum.QuestFrequency or {}
	NS.Print("Client: Forever; Enum.QuestFrequency Default=%s Daily=%s Weekly=%s ResetByScheduler=%s",
		tostring(E.Default), tostring(E.Daily), tostring(E.Weekly), tostring(E.ResetByScheduler))
end