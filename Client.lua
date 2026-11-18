-- QuestAutomator: the client adapter. Every API whose shape differs between WoW
-- Forever (Mainline UI, 16001) and Classic Era (1.15, 11509) is behind one of the
-- functions below. Feature code calls NS.Client.* and never tests WOW_PROJECT_ID.
-- One implementation table per flavour; both are complete. A function missing from
-- a flavour table is a bug, not a fallback. Ground truth for the Era shapes:
-- _EXTERNAL_APIS/wow_classic_era_quest_ui_api.md (Gethe classic_era, 2026-11-17).
--
-- Every adapter returns NAMED fields, never positional tuples, so the two flavours'
-- differently ordered C returns cannot be confused by a caller.
local ADDON, NS = ...

local Client = { flavour = nil }
NS.Client = Client

local flavours = { forever = {}, classic_era = {} }
local Forever, Era = flavours.forever, flavours.classic_era

--------------------------------------------------------------------------------
-- Shared helpers (not flavour specific).
--------------------------------------------------------------------------------
local function SafeCall(path, ...)
	return NS.Call(path, ...)
end

-- Hunter talent trees are the third tab on both clients.
Client.SURVIVAL_TAB_INDEX = 3

--------------------------------------------------------------------------------
-- Quest facts by questID.
--------------------------------------------------------------------------------
-- -> title string or nil
function Forever.QuestTitle(questID)
	return NS.SafeString(SafeCall("C_QuestLog.GetTitleForQuestID", questID))
end
function Era.QuestTitle(questID)
	return NS.SafeString(SafeCall("C_QuestLog.GetQuestInfo", questID))
end

-- Era: the log row for a quest the player is on, or nil. GetQuestLogTitle returns
-- title, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID, ...
local function EraLogRow(questID)
	local index = NS.SafeNumber(SafeCall("GetQuestLogIndexByID", questID))
	if not index or index <= 0 then return nil end
	local title, level, questTag, isHeader, isCollapsed, isComplete, frequency, id = SafeCall("GetQuestLogTitle", index)
	if NS.SafeBool(isHeader) then return nil end
	return {
		index = index,
		title = NS.SafeString(title),
		level = NS.SafeNumber(level),
		isComplete = NS.SafeNumber(isComplete),   -- 1 complete, -1 failed, nil in progress
		frequency = NS.SafeNumber(frequency) or 0,
		questID = NS.SafeNumber(id),
	}
end

-- -> true / false / nil (unknown)
function Forever.IsQuestTrivial(questID)
	return NS.SafeBool(SafeCall("C_QuestLog.IsQuestTrivial", questID))
end
function Era.IsQuestTrivial(questID)
	local row = EraLogRow(questID)
	if not row or not row.level then return nil end
	local playerLevel = NS.SafeNumber(SafeCall("UnitLevel", "player")) or 1
	local range = NS.SafeNumber(SafeCall("GetQuestGreenRange", "player")) or 5
	return row.level < playerLevel - range
end

-- -> true / false / nil (unknown)
function Forever.IsQuestRepeatable(questID)
	return NS.SafeBool(SafeCall("C_QuestLog.IsRepeatableQuest", questID))
end
function Era.IsQuestRepeatable(questID)
	local row = EraLogRow(questID)
	if not row then return nil end
	return row.frequency > 0
end

--------------------------------------------------------------------------------
-- Quest log walk: list of { questID, title, isComplete } for every real quest
-- (no headers, no hidden / task entries).
--------------------------------------------------------------------------------
function Forever.QuestLogEntries()
	local list = {}
	local n = NS.SafeNumber(SafeCall("C_QuestLog.GetNumQuestLogEntries")) or 0
	for index = 1, n do
		local info = SafeCall("C_QuestLog.GetInfo", index)
		if type(info) == "table" and not NS.SafeBool(info.isHeader) and not NS.SafeBool(info.isHidden) and not NS.SafeBool(info.isTask) then
			local questID = NS.SafeNumber(info.questID)
			if questID and questID > 0 then
				local complete = NS.SafeBool(SafeCall("C_QuestLog.IsComplete", questID)) and not NS.SafeBool(SafeCall("C_QuestLog.IsFailed", questID))
				list[#list + 1] = { questID = questID, title = NS.SafeString(info.title), isComplete = complete }
			end
		end
	end
	return list
end
function Era.QuestLogEntries()
	local list = {}
	local n = NS.SafeNumber(SafeCall("GetNumQuestLogEntries")) or 0
	for index = 1, n do
		local title, _, _, isHeader, _, isComplete, _, questID, _, _, _, _, isTask, _, _, isHidden = SafeCall("GetQuestLogTitle", index)
		questID = NS.SafeNumber(questID)
		if not NS.SafeBool(isHeader) and not NS.SafeBool(isHidden) and not NS.SafeBool(isTask) and questID and questID > 0 then
			list[#list + 1] = { questID = questID, title = NS.SafeString(title), isComplete = NS.SafeNumber(isComplete) == 1 }
		end
	end
	return list
end

-- Experience a completed log quest gives on hand-in; 0 when unknown.
function Forever.QuestRewardXP(questID)
	return NS.SafeNumber(SafeCall("GetQuestLogRewardXP", questID)) or 0
end
function Era.QuestRewardXP(questID)
	-- The Era global reads the *selected* log entry: select, read, restore.
	local index = NS.SafeNumber(SafeCall("GetQuestLogIndexByID", questID))
	if not index or index <= 0 then return 0 end
	local previous = NS.SafeNumber(SafeCall("GetQuestLogSelection"))
	SafeCall("SelectQuestLogEntry", index)
	local xp = NS.SafeNumber(SafeCall("GetQuestLogRewardXP")) or 0
	if previous and previous ~= index then SafeCall("SelectQuestLogEntry", previous) end
	return xp
end

--------------------------------------------------------------------------------
-- Greeting panel row (the plain QuestFrame list, no gossip).
-- -> { isTrivial, frequency, isRepeatable, questID } ; questID may be nil on Era.
--------------------------------------------------------------------------------
function Forever.AvailableQuestInfo(index)
	local isTrivial, frequency, isRepeatable, _, questID = SafeCall("GetAvailableQuestInfo", index)
	return {
		isTrivial = NS.SafeBool(isTrivial),
		frequency = NS.SafeNumber(frequency) or 0,
		isRepeatable = NS.SafeBool(isRepeatable),
		questID = NS.SafeNumber(questID),
	}
end
function Era.AvailableQuestInfo(index)
	local isTrivial, isDaily, isRepeatable = SafeCall("GetAvailableQuestInfo", index)
	return {
		isTrivial = NS.SafeBool(isTrivial),
		frequency = NS.SafeBool(isDaily) and 1 or 0,
		isRepeatable = NS.SafeBool(isRepeatable),
		questID = nil,
	}
end

-- Active (hand-in) greeting row questID, or nil when the client cannot tell.
function Forever.ActiveQuestID(index)
	return NS.SafeNumber(SafeCall("GetActiveQuestID", index))
end
function Era.ActiveQuestID(index)
	if type(_G.GetActiveQuestID) == "function" then
		return NS.SafeNumber(SafeCall("GetActiveQuestID", index))
	end
	return nil
end

--------------------------------------------------------------------------------
-- Item stats: { STAT_KEY = amount } keyed like Rules.STAT_KEYS, or nil.
--------------------------------------------------------------------------------
local function NormalizeStats(t)
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
function Forever.ItemStats(link)
	return NormalizeStats(SafeCall("C_Item.GetItemStats", link))
end
function Era.ItemStats(link)
	if type(_G.GetItemStats) == "function" then
		return NormalizeStats(SafeCall("GetItemStats", link))
	end
	return NormalizeStats(SafeCall("C_Item.GetItemStats", link))
end

--------------------------------------------------------------------------------
-- Talents: points spent per tree in display order.
-- -> { groups = { { name, spent, orderIndex, skillLineID } ... }, source = "traits" | "talents" | "none" }
--------------------------------------------------------------------------------
function Forever.TalentGroups()
	local result = { groups = {}, source = "none" }
	local group = NS.SafeNumber(SafeCall("C_SpecializationInfo.GetActiveSpecGroup")) or 1
	local configID = NS.SafeNumber(SafeCall("C_SpecializationInfo.GetCombatConfigIDForSpecGroup", group))
		or NS.SafeNumber(SafeCall("C_ClassTalents.GetActiveConfigID"))
	if not configID then return result end
	local configInfo = SafeCall("C_Traits.GetConfigInfo", configID)
	local treeID = type(configInfo) == "table" and type(configInfo.treeIDs) == "table" and NS.SafeNumber(configInfo.treeIDs[1]) or nil
	if not treeID then return result end
	local displayInfos = SafeCall("C_Traits.GetGroupDisplayInfoByTreeID", treeID)
	if type(displayInfos) ~= "table" or #displayInfos == 0 then return result end
	local groupIDs = {}
	for _, info in ipairs(displayInfos) do
		local id = NS.SafeNumber(info.groupID)
		if id then groupIDs[#groupIDs + 1] = id end
	end
	local spentByGroup = {}
	local currencyInfos = SafeCall("C_Traits.GetGroupCurrencyInfo", configID, groupIDs)
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
	return result
end
function Era.TalentGroups()
	local result = { groups = {}, source = "none" }
	local tabs = NS.SafeNumber(SafeCall("GetNumTalentTabs")) or 3
	for tab = 1, tabs do
		-- specId, name, description, icon, role, primaryStat, pointsSpent, background
		local _, name, _, _, _, _, pointsSpent = SafeCall("C_SpecializationInfo.GetSpecializationInfo", tab)
		if name == nil and pointsSpent == nil then break end
		result.groups[#result.groups + 1] = {
			name = NS.SafeString(name),
			skillLineID = nil,
			orderIndex = tab,
			spent = NS.SafeNumber(pointsSpent) or 0,
		}
	end
	if #result.groups > 0 then result.source = "talents" end
	return result
end

--------------------------------------------------------------------------------
-- Level cap.
--------------------------------------------------------------------------------
local function SharedMaxLevel(fallback)
	local util = GameRulesUtil
	if type(util) == "table" and type(util.GetEffectiveMaxLevelForPlayer) == "function" then
		local ok, level = pcall(util.GetEffectiveMaxLevelForPlayer)
		level = ok and NS.SafeNumber(level) or nil
		if level and level > 0 then return level end
	end
	return NS.SafeNumber(SafeCall("GetMaxPlayerLevel")) or fallback
end
function Forever.MaxLevel(fallback) return SharedMaxLevel(fallback) end
function Era.MaxLevel(fallback) return SharedMaxLevel(fallback) end

--------------------------------------------------------------------------------
-- Reward panels: where Blizzard draws reward buttons, and how to read the
-- choices shown. Both flavours draw the NPC detail / reward panels through
-- QuestInfo_Display; only the quest log differs (Era uses QuestFrameItems_Update
-- and QuestLogItemN buttons).
--
-- RewardLayoutHooks() -> list of global function names to hooksecurefunc.
-- RewardContext()     -> nil when no reward panel is visible, else
--   { questID, questLog = bool, buttons = { Button... }, source = Rewards source }
--   Each Button carries :GetID() == choice index for type "choice" items.
--------------------------------------------------------------------------------
local function FrameShown(frame)
	if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false end
	local ok, shown = pcall(frame.IsShown, frame)
	return ok and shown == true
end

local function QuestInfoRewardButtons(rewardsFrame)
	local buttons = {}
	for _, button in ipairs(rewardsFrame.RewardButtons or {}) do
		if type(button) == "table" and FrameShown(button) and button.type == "choice" and button.objectType == "item" then
			buttons[#buttons + 1] = button
		end
	end
	return buttons
end

-- NPC panels (shared): QuestInfoFrame.rewardsFrame while QuestFrame is up.
local function NpcRewardContext()
	local info = QuestInfoFrame
	if type(info) ~= "table" or info.questLog then return nil end
	local rewardsFrame = info.rewardsFrame
	if type(rewardsFrame) ~= "table" or not FrameShown(rewardsFrame) then return nil end
	local questID = NS.SafeNumber(SafeCall("GetQuestID"))
	if questID == 0 then questID = nil end
	return { questID = questID, questLog = false, buttons = QuestInfoRewardButtons(rewardsFrame), frame = rewardsFrame, source = NS.Rewards.OFFER }
end

function Forever.RewardLayoutHooks()
	return { "QuestInfo_Display", "QuestInfo_ShowRewards" }
end
function Forever.RewardContext()
	local info = QuestInfoFrame
	if type(info) ~= "table" then return nil end
	if info.questLog then
		local rewardsFrame = info.rewardsFrame
		if type(rewardsFrame) ~= "table" or not FrameShown(rewardsFrame) then return nil end
		local questID = NS.SafeNumber(SafeCall("C_QuestLog.GetSelectedQuest"))
		if not questID or questID == 0 then return nil end
		return { questID = questID, questLog = true, buttons = QuestInfoRewardButtons(rewardsFrame), frame = rewardsFrame, source = NS.Rewards.LogSource(questID) }
	end
	return NpcRewardContext()
end

function Era.RewardLayoutHooks()
	return { "QuestInfo_Display", "QuestInfo_ShowRewards", "QuestFrameItems_Update" }
end
function Era.RewardContext()
	local npc = NpcRewardContext()
	if npc then return npc end
	-- Quest log: QuestLogFrame + QuestLogItem1..MAX_NUM_ITEMS, .type "choice", .rewardType "item"
	local logFrame = QuestLogFrame
	if not FrameShown(logFrame) then return nil end
	local questID = NS.SafeNumber(SafeCall("GetQuestLogSelectedID"))
	if not questID or questID == 0 then return nil end
	local buttons = {}
	for i = 1, (MAX_NUM_ITEMS or 10) do
		local button = _G["QuestLogItem" .. i]
		if type(button) == "table" and FrameShown(button) and button.type == "choice" and (button.rewardType == "item" or button.rewardType == nil) then
			buttons[#buttons + 1] = button
		end
	end
	return { questID = questID, questLog = true, buttons = buttons, frame = logFrame, source = NS.Rewards.LogSource(questID) }
end

--------------------------------------------------------------------------------
-- Quest-log reward source arguments. Forever's log functions take questID; Era's
-- read the selected quest and take none.
--------------------------------------------------------------------------------
function Forever.LogChoiceCount(questID) return SafeCall("GetNumQuestLogChoices", questID) end
function Forever.LogChoiceInfo(i, questID) return SafeCall("GetQuestLogChoiceInfo", i, questID) end
function Forever.LogChoiceTooltip(i, questID) return SafeCall("C_TooltipInfo.GetQuestLogItem", "choice", i, questID) end
function Era.LogChoiceCount(questID) return SafeCall("GetNumQuestLogChoices") end
function Era.LogChoiceInfo(i, questID) return SafeCall("GetQuestLogChoiceInfo", i) end
function Era.LogChoiceTooltip(i, questID) return SafeCall("C_TooltipInfo.GetQuestLogItem", "choice", i) end

--------------------------------------------------------------------------------
-- Selection and debug.
--------------------------------------------------------------------------------
local function SelectFlavour()
	if WOW_PROJECT_ID ~= nil and WOW_PROJECT_CLASSIC ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
		return "classic_era"
	end
	return "forever"
end

Client.flavour = SelectFlavour()
local impl = flavours[Client.flavour]
for name, fn in pairs(impl) do
	Client[name] = fn
end
NS.features["Client." .. Client.flavour] = true

-- Every adapter name, so a missing one shows up in /qam debug for either flavour.
Client.ADAPTERS = {}
for name in pairs(Forever) do Client.ADAPTERS[#Client.ADAPTERS + 1] = name end
table.sort(Client.ADAPTERS)
for _, name in ipairs(Client.ADAPTERS) do
	if type(Era[name]) ~= "function" then NS.WarnOnce("client:" .. name, "classic_era adapter missing: " .. name) end
end

function Client.DebugReport()
	NS.Print("Client: flavour %s (WOW_PROJECT_ID=%s), adapters: %s", Client.flavour, tostring(WOW_PROJECT_ID), table.concat(Client.ADAPTERS, ", "))
end