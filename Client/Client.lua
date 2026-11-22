-- Quest Automator: the client interface. The logic (Automation.lua and friends)
-- only ever calls NS.Client.*; it never sees a positional C tuple, a raw
-- frequency number, an Enum.* or an LE_* constant. One implementation file per
-- game flavour conforms to the interface declared here:
--
--   Client/Client_Forever.lua     WoW Forever (Mainline UI, interface 16001)
--   Client/Client_ClassicEra.lua  Classic Era / Anniversary / Hardcore (1.15, 11509)
--
-- Load order (TOC): Client.lua, Client_Forever.lua, Client_ClassicEra.lua, then
-- Client_Select.lua picks the one matching WOW_PROJECT_ID and verifies every
-- interface method is implemented. A missing method is a load-time warning, not
-- a silent nil at the NPC.
local ADDON, NS = ...

local Client = {}
NS.Client = Client
NS.ClientFlavours = {}  -- name -> implementation table, filled by the flavour files

--------------------------------------------------------------------------------
-- String values the logic sees for quest frequency.
--------------------------------------------------------------------------------
Client.FREQUENCY_DEFAULT = "default"      -- an ordinary, one-time quest
Client.FREQUENCY_DAILY = "daily"
Client.FREQUENCY_WEEKLY = "weekly"
Client.FREQUENCY_SCHEDULED = "scheduled"  -- resets on a server schedule (Forever's ResetByScheduler)

-- Recurring = the quest comes back on a timer. The user's "repeatable" setting
-- covers these plus the explicit isRepeatable flag.
function Client.IsRecurringFrequency(frequency)
	return frequency == Client.FREQUENCY_DAILY or frequency == Client.FREQUENCY_WEEKLY or frequency == Client.FREQUENCY_SCHEDULED
end

--------------------------------------------------------------------------------
-- Shared helper for the flavour files: map a numeric frequency through a
-- { number -> FREQUENCY_* } table, warning once on a value nobody documented.
--------------------------------------------------------------------------------
function Client.DecodeFrequency(map, value)
	value = NS.SafeNumber(value)
	if value == nil then return Client.FREQUENCY_DEFAULT end
	local name = map[value]
	if not name then
		NS.WarnOnce("frequency:" .. tostring(value), "unknown quest frequency value " .. tostring(value))
		return Client.FREQUENCY_DEFAULT
	end
	return name
end

--------------------------------------------------------------------------------
-- The interface. Every flavour file must implement each of these.
--------------------------------------------------------------------------------
Client.INTERFACE = {
	-- GossipQuestInfo(info)  info = one entry of C_GossipInfo.GetAvailableQuests() / GetActiveQuests()
	--   -> { questID, title, isTrivial, isRepeatable, isComplete, frequency = FREQUENCY_* }
	"GossipQuestInfo",

	-- AvailableQuestInfo(index)  greeting panel row (GetAvailableQuestInfo)
	--   -> { questID (may be nil), isTrivial, isRepeatable, frequency = FREQUENCY_*, rawFrequency (log only) }
	"AvailableQuestInfo",

	-- ActiveQuestID(index)  greeting panel hand-in row -> questID or nil
	"ActiveQuestID",

	-- QuestTitle(questID) -> string or nil
	"QuestTitle",

	-- IsQuestTrivial(questID) -> bool (false when the client cannot tell)
	"IsQuestTrivial",

	-- IsQuestRepeatable(questID) -> bool (false when the client cannot tell)
	"IsQuestRepeatable",

	-- IsQuestComplete(questID) -> bool: in the log and ready to hand in
	"IsQuestComplete",

	-- QuestLogQuests()  every real quest in the log (no headers, hidden or task rows)
	--   -> list of { questID, title, isComplete }
	"QuestLogQuests",

	-- SelectedQuestLogQuestID() -> the questID selected in the quest log, or nil
	"SelectedQuestLogQuestID",

	-- QuestLogChoiceSource(questID)  the reward CHOICES of a quest in the log, read
	-- once and snapshotted (Era must select the log entry to read them; the previous
	-- selection is restored). Same shape Rewards.Gather consumes:
	--   { name, questID, Count(), Info(i) -> name, texture, count, quality, isUsable, itemID,
	--     Link(i) -> item link, Tooltip(i) -> C_TooltipInfo data or nil }
	"QuestLogChoiceSource",

	-- QuestLogRewardXP(questID) -> experience a completed log quest gives on hand-in; 0 if unknown
	"QuestLogRewardXP",

	-- StatWeightOverrides()  flavour-specific corrections to the default class stat
	-- weights (Rules.WEIGHTS), applied once at load by Rules.ApplyClientWeightOverrides.
	--   -> { CLASS = { STAT_KEY = weight, ... }, ... }   (empty table = no differences)
	-- The game rules differ per flavour: on Forever druids benefit from weapon DPS and
	-- weapon procs in forms (MELEE_DPS matters); on Classic Era druid weapon damage is
	-- ignored in forms so a hammer is never an upgrade on its DPS. Keep every such
	-- "the game itself works differently here" fact in the flavour file, not in Rules.
	"StatWeightOverrides",

	-- DebugReport()  one /qam debug line describing the flavour and its constants
	"DebugReport",
}