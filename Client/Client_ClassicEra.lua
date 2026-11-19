-- Quest Automator: Classic Era client (1.15.x, interface 11509; also Anniversary
-- and Hardcore). Implements the interface in Client/Client.lua.
-- Ground truth:
--   _EXTERNAL_APIS/wow_classic_era_quest_ui_api.md (Gethe classic_era, 2026-11-17)
--   _ref/blizzard/classic_era/QuestFrame_Classic.lua :379  GetAvailableQuestInfo returns
--   _ref/blizzard/classic_era/GossipFrame.lua :27           gossip tables use Enum.QuestFrequency
--   _ref/blizzard/classic_era/QuestLogDocumentation.lua    Era C_QuestLog has NO IsQuestTrivial /
--                                                          IsRepeatableQuest / GetTitleForQuestID / IsComplete
--   warcraft.wiki.gg API_GetAvailableQuestInfo, API_GetQuestLogTitle, Patch_6.0.2/API_changes
local ADDON, NS = ...
local Client = NS.Client

local Era = {}
NS.ClientFlavours.classic_era = Era

--------------------------------------------------------------------------------
-- Frequency encoding. Era uses TWO scales depending on the API:
--
-- (a) Enum.QuestFrequency for the table-returning C_GossipInfo APIs (Era
--     GossipFrame.lua compares questInfo.frequency to Enum.QuestFrequency.Daily).
--     QuestLogDocumentation.lua: Default = 0, Daily = 1, Weekly = 2, ResetByScheduler = 3
--
-- (b) LE_QUEST_FREQUENCY_* "legacy globals" for the flat-return APIs:
--     GetAvailableQuestInfo(i) 2nd return and GetQuestLogTitle(i) 7th return.
--     "Legacy globals" = Blizzard's pre-Enum Lua constants (LE_* prefix) from
--     patch 6.0.2, still what Classic's C code encodes these returns in.
--     Patch 6.0.2 API changes: DEFAULT = 1, DAILY = 2, WEEKLY = 3
--     Observed on Era 1.15.9: an ordinary greeting quest reports 1.
--
-- The two scales disagree on what 1 means (Daily vs Default), which is exactly
-- how the forkbase's "frequency > 0 = repeatable" test rejected every ordinary
-- greeting quest on Era.
--------------------------------------------------------------------------------
local ENUM_FREQUENCY = {}
do
	local E = Enum and Enum.QuestFrequency or {}
	ENUM_FREQUENCY[E.Default or 0] = Client.FREQUENCY_DEFAULT
	ENUM_FREQUENCY[E.Daily or 1] = Client.FREQUENCY_DAILY
	ENUM_FREQUENCY[E.Weekly or 2] = Client.FREQUENCY_WEEKLY
	ENUM_FREQUENCY[E.ResetByScheduler or 3] = Client.FREQUENCY_SCHEDULED
end

local LEGACY_FREQUENCY = {}
do
	LEGACY_FREQUENCY[LE_QUEST_FREQUENCY_DEFAULT or 1] = Client.FREQUENCY_DEFAULT
	LEGACY_FREQUENCY[LE_QUEST_FREQUENCY_DAILY or 2] = Client.FREQUENCY_DAILY
	LEGACY_FREQUENCY[LE_QUEST_FREQUENCY_WEEKLY or 3] = Client.FREQUENCY_WEEKLY
end

--------------------------------------------------------------------------------
-- Quest log row for a quest the player is on (legacy GetQuestLogTitle).
-- Returns: title, level, questTag, isHeader, isCollapsed, isComplete, frequency(LEGACY), questID, ...
--------------------------------------------------------------------------------
local function LogRow(questID)
	local index = NS.SafeNumber(NS.Call("GetQuestLogIndexByID", questID))
	if not index or index <= 0 then return nil end
	local title, level, _, isHeader, _, isComplete, frequency = NS.Call("GetQuestLogTitle", index)
	if NS.SafeBool(isHeader) then return nil end
	return {
		title = NS.SafeString(title),
		level = NS.SafeNumber(level),
		isComplete = NS.SafeNumber(isComplete), -- 1 complete, -1 failed, nil in progress
		frequency = Client.DecodeFrequency(LEGACY_FREQUENCY, frequency),
	}
end

--------------------------------------------------------------------------------
-- Interface.
--------------------------------------------------------------------------------
function Era.GossipQuestInfo(info)
	return {
		questID = NS.SafeNumber(info.questID),
		title = NS.SafeString(info.title),
		isTrivial = NS.SafeBool(info.isTrivial),
		isRepeatable = NS.SafeBool(info.repeatable),
		isComplete = NS.SafeBool(info.isComplete),
		frequency = Client.DecodeFrequency(ENUM_FREQUENCY, info.frequency),
	}
end

-- GetAvailableQuestInfo(i) -> isTrivial, frequency(LEGACY), isRepeatable, isLegendary.  No questID on Era.
function Era.AvailableQuestInfo(index)
	local isTrivial, frequency, isRepeatable = NS.Call("GetAvailableQuestInfo", index)
	return {
		questID = nil,
		isTrivial = NS.SafeBool(isTrivial),
		isRepeatable = NS.SafeBool(isRepeatable),
		frequency = Client.DecodeFrequency(LEGACY_FREQUENCY, frequency),
		rawFrequency = frequency,
	}
end

-- Not referenced by the Era UI; use it only if the client happens to have it.
function Era.ActiveQuestID(index)
	if type(_G.GetActiveQuestID) ~= "function" then return nil end
	return NS.SafeNumber(NS.Call("GetActiveQuestID", index))
end

function Era.QuestTitle(questID)
	return NS.SafeString(NS.Call("C_QuestLog.GetQuestInfo", questID))
end

-- Trivial = grey: log level below player level minus the green range. Only
-- answerable for a quest in the log.
function Era.IsQuestTrivial(questID)
	if not questID then return false end
	local row = LogRow(questID)
	if not row or not row.level then return false end
	local playerLevel = NS.SafeNumber(NS.Call("UnitLevel", "player")) or 1
	local range = NS.SafeNumber(NS.Call("GetQuestGreenRange", "player")) or 5
	return row.level < playerLevel - range
end

-- The log exposes only daily / weekly; plain repeatables are flagged by the
-- gossip / greeting offer, which the logic reads through GossipQuestInfo /
-- AvailableQuestInfo.
function Era.IsQuestRepeatable(questID)
	if not questID then return false end
	local row = LogRow(questID)
	return row ~= nil and Client.IsRecurringFrequency(row.frequency)
end

-- Era's gossip entries leave isComplete unset. The legacy global IsQuestComplete(questID)
-- (QuestFrame_Classic) answers directly; the quest-log row is the fallback.
function Era.IsQuestComplete(questID)
	if not questID then return false end
	local answer = NS.Call("IsQuestComplete", questID)
	if answer ~= nil then return NS.SafeBool(answer) end
	local row = LogRow(questID)
	return row ~= nil and row.isComplete == 1
end

-- GetQuestLogTitle(i) -> title, level, questTag, isHeader, isCollapsed, isComplete,
-- frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isBounty, isStory, isHidden
function Era.QuestLogQuests()
	local list = {}
	local n = NS.SafeNumber(NS.Call("GetNumQuestLogEntries")) or 0
	for index = 1, n do
		local title, _, _, isHeader, _, isComplete, _, questID, _, _, _, _, isTask, _, _, isHidden = NS.Call("GetQuestLogTitle", index)
		questID = NS.SafeNumber(questID)
		if not NS.SafeBool(isHeader) and not NS.SafeBool(isHidden) and not NS.SafeBool(isTask) and questID and questID > 0 then
			list[#list + 1] = { questID = questID, title = NS.SafeString(title), isComplete = NS.SafeNumber(isComplete) == 1 }
		end
	end
	return list
end

function Era.SelectedQuestLogQuestID()
	local id = NS.SafeNumber(NS.Call("GetQuestLogSelectedID"))
	if id and id > 0 then return id end
	return nil
end

function Era.DebugReport()
	local E = Enum and Enum.QuestFrequency or {}
	NS.Print("Client: Classic Era; Enum.QuestFrequency Default=%s Daily=%s Weekly=%s | LE_QUEST_FREQUENCY DEFAULT=%s DAILY=%s WEEKLY=%s",
		tostring(E.Default), tostring(E.Daily), tostring(E.Weekly),
		tostring(LE_QUEST_FREQUENCY_DEFAULT), tostring(LE_QUEST_FREQUENCY_DAILY), tostring(LE_QUEST_FREQUENCY_WEEKLY))
end