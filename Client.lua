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

-- Era's quest-log globals (GetQuestLogRewardXP, GetNumQuestLogChoices,
-- GetQuestLogChoiceInfo, C_TooltipInfo.GetQuestLogItem) read the *selected* log
-- entry and take no questID. Select the quest, call fn, restore the selection.
-- Returns fn's results, or nothing when the quest is not in the log.
local function EraWithLogSelection(questID, fn)
	local index = NS.SafeNumber(SafeCall("GetQuestLogIndexByID", questID))
	if not index or index <= 0 then return nil end
	local previous = NS.SafeNumber(SafeCall("GetQuestLogSelection"))
	if previous ~= index then SafeCall("SelectQuestLogEntry", index) end
	local results = { fn() }
	if previous and previous ~= index then SafeCall("SelectQuestLogEntry", previous) end
	return unpack(results, 1, table.maxn(results))
end
function Era.QuestRewardXP(questID)
	-- The Era global reads the *selected* log entry: select, read, restore.
	return NS.SafeNumber(EraWithLogSelection(questID, function() return SafeCall("GetQuestLogRewardXP") end)) or 0
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
-- Equipped gear. WornItemLevel(equipLoc) -> { itemLevel, slotID, link } for the
-- weakest slot the piece could go into (paired rings/trinkets/weapons compare
-- against the lower one), itemLevel 0 and link nil for an empty slot; nil when
-- the equipLoc is not a comparable slot. Shared: both clients have
-- GetInventoryItemLink and C_Item.GetItemInfo.
--------------------------------------------------------------------------------
local function SharedWornItemLevel(equipLoc)
	local slots = NS.Rules.EQUIP_SLOTS[equipLoc or ""]
	if not slots or NS.Rules.UNCOMPARED_SLOTS[equipLoc or ""] then return nil end
	local weakest
	for _, slotID in ipairs(slots) do
		local link = NS.SafeString(SafeCall("GetInventoryItemLink", "player", slotID))
		local level = 0
		if link then
			local _, _, _, ilvl = SafeCall("C_Item.GetItemInfo", link)
			level = NS.SafeNumber(ilvl) or 0
		end
		if not weakest or level < weakest.itemLevel then
			weakest = { itemLevel = level, slotID = slotID, link = link }
		end
	end
	-- A two-hander replaces main hand AND off hand: compare against the stronger
	-- of the two so a 2H is not called an upgrade over an empty off hand alone.
	if equipLoc == "INVTYPE_2HWEAPON" then
		local offLink = NS.SafeString(SafeCall("GetInventoryItemLink", "player", 17))
		if offLink then
			local _, _, _, offIlvl = SafeCall("C_Item.GetItemInfo", offLink)
			offIlvl = NS.SafeNumber(offIlvl) or 0
			if offIlvl > weakest.itemLevel then weakest = { itemLevel = offIlvl, slotID = 17, link = offLink } end
		end
	end
	return weakest
end
function Forever.WornItemLevel(equipLoc) return SharedWornItemLevel(equipLoc) end
function Era.WornItemLevel(equipLoc) return SharedWornItemLevel(equipLoc) end

--------------------------------------------------------------------------------
-- Item value in copper for the "most valuable" tier. valueSource "vendor" is the
-- only provider today; "auction" and "disenchant" fall back to vendor until a
-- provider (Auctionator / TSM / a DE library) is registered via
-- Client.RegisterValueProvider(name, fn(link, count) -> copper or nil).
--------------------------------------------------------------------------------
local valueProviders = {}
function Client.RegisterValueProvider(name, fn)
	valueProviders[name] = fn
	NS.features["value:" .. name] = true
end

local function SharedItemValue(link, count, sellPrice, valueSource)
	count = count or 1
	local provider = valueSource and valueSource ~= "vendor" and valueProviders[valueSource] or nil
	if provider and link then
		local ok, copper = pcall(provider, link, count)
		copper = ok and NS.SafeNumber(copper) or nil
		if copper and copper > 0 then return copper, valueSource end
	end
	return (NS.SafeNumber(sellPrice) or 0) * count, "vendor"
end
function Forever.ItemValue(link, count, sellPrice, valueSource) return SharedItemValue(link, count, sellPrice, valueSource) end
function Era.ItemValue(link, count, sellPrice, valueSource) return SharedItemValue(link, count, sellPrice, valueSource) end

--------------------------------------------------------------------------------
-- Weapon skill. HasWeaponSkill(subclass) -> true / false / nil (cannot tell).
-- Era: the skill window (GetNumSkillLines / GetSkillLineInfo) lists trained
-- weapon skills by name. Forever: weapon skills were removed with the trait
-- system; every learnable weapon counts as usable (nil = cannot tell).
--------------------------------------------------------------------------------
function Forever.HasWeaponSkill(subclass)
	return nil
end
function Era.HasWeaponSkill(subclass)
	local wanted = NS.SafeString(SafeCall("C_Item.GetItemSubClassInfo", NS.Rules.CLASS_WEAPON, subclass))
		or NS.Rules.WEAPON_SKILL_NAMES[subclass]
	if not wanted then return nil end
	local n = NS.SafeNumber(SafeCall("GetNumSkillLines"))
	if not n then return nil end
	for i = 1, n do
		local name, isHeader = SafeCall("GetSkillLineInfo", i)
		name = NS.SafeString(name)
		if name and not NS.SafeBool(isHeader) and name == wanted then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- Tooltip stat format strings, keyed by ITEM_MOD_* tag (plus DPS_TEMPLATE,
-- ARMOR_TEMPLATE, ITEM_SPELL_TRIGGER_ONEQUIP). Rewards.FormatsFor tries the
-- client's live global first, then these. "%c" = sign, "%s"/"%d" = number,
-- "%%" = a literal percent sign.
--
-- Forever: GlobalStrings of build 1.60.1.69893 (wago.tools), enUS and zhCN.
-- Era: the green "Equip:" lines are vanilla spell descriptions, not GlobalStrings,
-- so they are written out here (enUS; zhCN descriptions not verified, the plain
-- "+N Stat" lines share the Forever strings). Percent-based hit/crit/dodge/parry/
-- block are mapped onto the *_RATING keys: the weights are per point and a vanilla
-- percent is worth about one rating step at the levels that quest rewards cover.
--------------------------------------------------------------------------------
local SHARED_STAT_FORMATS = {
	ITEM_MOD_MANA = { "%c%s Mana", "%c%s 法力" },
	ITEM_MOD_HEALTH = { "%c%s Health", "%c%s 生命" },
	ITEM_MOD_AGILITY = { "%c%s Agility", "%c%s 敏捷" },
	ITEM_MOD_STRENGTH = { "%c%s Strength", "%c%s 力量" },
	ITEM_MOD_SPIRIT = { "%c%s Spirit", "%c%s 精神" },
	ITEM_MOD_STAMINA = { "%c%s Stamina", "%c%s 耐力" },
	ITEM_MOD_INTELLECT = { "%c%s Intellect", "%c%s 智力" },
	DPS_TEMPLATE = { "(%s damage per second)", "（每秒伤害%s）" },
	ARMOR_TEMPLATE = { "%s Armor", "%s点护甲" },
	ITEM_SPELL_TRIGGER_ONEQUIP = { "Equip:", "装备：" },
}

local function MergeFormats(base, extra)
	local out = {}
	for tag, list in pairs(base) do
		out[tag] = {}
		for _, fmt in ipairs(list) do out[tag][#out[tag] + 1] = fmt end
	end
	for tag, list in pairs(extra) do
		out[tag] = out[tag] or {}
		for _, fmt in ipairs(list) do out[tag][#out[tag] + 1] = fmt end
	end
	return out
end

Forever.STAT_FORMATS = MergeFormats(SHARED_STAT_FORMATS, {
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
})

Era.STAT_FORMATS = MergeFormats(SHARED_STAT_FORMATS, {
	ITEM_MOD_DEFENSE_SKILL_RATING = { "Increased Defense +%s.", "Increased Defense +%s", "%c%s Defense" },
	ITEM_MOD_DODGE_RATING = { "Increases your chance to dodge an attack by %s%%.", "%c%s%% Dodge" },
	ITEM_MOD_PARRY_RATING = { "Increases your chance to parry an attack by %s%%.", "%c%s%% Parry" },
	ITEM_MOD_BLOCK_RATING = { "Increases your chance to block attacks with a shield by %s%%.", "%c%s%% Block" },
	ITEM_MOD_HIT_RATING = { "Improves your chance to hit by %s%%.", "Improves your chance to hit with spells by %s%%.", "%c%s%% Hit" },
	ITEM_MOD_CRIT_RATING = { "Improves your chance to get a critical strike by %s%%.", "Improves your chance to get a critical strike with spells by %s%%.", "%c%s%% Critical Strike" },
	ITEM_MOD_SPELL_HEALING_DONE = { "Increases healing done by spells and effects by up to %s.", "Increases healing done by magical spells and effects by up to %s." },
	ITEM_MOD_SPELL_DAMAGE_DONE = { "Increases damage done by magical spells and effects by up to %s." },
	ITEM_MOD_SPELL_POWER = { "Increases damage and healing done by magical spells and effects by up to %s." },
	ITEM_MOD_ATTACK_POWER = { "%c%s Attack Power.", "%c%s Attack Power", "Increases attack power by %s." },
	ITEM_MOD_RANGED_ATTACK_POWER = { "%c%s ranged Attack Power.", "%c%s ranged Attack Power", "Increases ranged attack power by %s." },
	ITEM_MOD_FERAL_ATTACK_POWER = { "%c%s Attack Power in Cat, Bear, Dire Bear, and Moonkin forms only." },
	ITEM_MOD_MANA_REGENERATION = { "Restores %s mana per 5 sec.", "Restores %s mana every 5 sec." },
	ITEM_MOD_HEALTH_REGENERATION = { "Restores %s health per 5 sec.", "Restores %s health every 5 sec." },
	ITEM_MOD_BLOCK_VALUE = { "Increases the block value of your shield by %s." },
})

function Forever.StatFormats() return Forever.STAT_FORMATS end
function Era.StatFormats() return Era.STAT_FORMATS end

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
-- read the selected quest and take none, so the Era adapters select the quest
-- for the duration of the call and restore the previous selection.
--------------------------------------------------------------------------------
function Forever.LogChoiceCount(questID) return SafeCall("GetNumQuestLogChoices", questID) end
function Forever.LogChoiceInfo(i, questID) return SafeCall("GetQuestLogChoiceInfo", i, questID) end
function Forever.LogChoiceTooltip(i, questID) return SafeCall("C_TooltipInfo.GetQuestLogItem", "choice", i, questID) end
function Era.LogChoiceCount(questID)
	return EraWithLogSelection(questID, function() return SafeCall("GetNumQuestLogChoices") end)
end
function Era.LogChoiceInfo(i, questID)
	return EraWithLogSelection(questID, function() return SafeCall("GetQuestLogChoiceInfo", i) end)
end
function Era.LogChoiceTooltip(i, questID)
	return EraWithLogSelection(questID, function() return SafeCall("C_TooltipInfo.GetQuestLogItem", "choice", i) end)
end

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