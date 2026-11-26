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

-- Era's quest-log reward globals (GetNumQuestLogChoices, GetQuestLogChoiceInfo,
-- GetQuestLogItemLink, GetQuestLogRewardXP, C_TooltipInfo.GetQuestLogItem) take
-- NO questID: they read the SELECTED log entry. Select the quest, call fn,
-- restore the previous selection (including 0 = nothing selected).
local function WithLogSelection(questID, fn)
	local index = NS.SafeNumber(NS.Call("GetQuestLogIndexByID", questID))
	if not index or index <= 0 then return nil end
	local previous = NS.SafeNumber(NS.Call("GetQuestLogSelection"))
	if previous ~= index then NS.Call("SelectQuestLogEntry", index) end
	local ok, result = pcall(fn)
	if previous ~= nil and previous ~= index then NS.Call("SelectQuestLogEntry", previous) end
	if not ok then error(result) end
	return result
end

-- GetQuestLogChoiceInfo(i) on Era -> name, texture, count, quality, isUsable, itemID (6 returns)
function Era.QuestLogChoiceSource(questID)
	local choices = WithLogSelection(questID, function()
		local list = {}
		local count = NS.SafeNumber(NS.Call("GetNumQuestLogChoices")) or 0
		for i = 1, count do
			local name, texture, num, quality, isUsable, itemID = NS.Call("GetQuestLogChoiceInfo", i)
			local link = NS.SafeString(NS.Call("GetQuestLogItemLink", "choice", i))
			itemID = NS.SafeNumber(itemID) or (link and tonumber(link:match("item:(%d+)")))
			if itemID and not link then
				local _, itemLink = NS.Call("C_Item.GetItemInfo", itemID)
				link = NS.SafeString(itemLink) or ("item:" .. itemID)
			end
			list[i] = { info = { name, texture, num, quality, isUsable, itemID }, link = link, itemID = itemID }
		end
		return list
	end) or {}
	return {
		name = "log", questID = questID,
		Count = function() return #choices end,
		Info = function(i) return unpack(choices[i].info, 1, 6) end,
		Link = function(i) return choices[i].link end,
		Tooltip = function(i) local link = choices[i].link; if link then return NS.Call("C_TooltipInfo.GetHyperlink", link) end end,
	}
end

function Era.QuestLogRewardXP(questID)
	return NS.SafeNumber(WithLogSelection(questID, function() return NS.Call("GetQuestLogRewardXP") end)) or 0
end

-- CLASSIC ERA RULE: a druid's Cat / Bear form damage IGNORES weapon DPS (form attack
-- is derived from level and attack power; the weapon's own damage range is irrelevant).
-- So a mace or staff is never an upgrade for an Era druid on its DPS - only on its
-- stats. Zero the melee DPS weight; everything else keeps the shared default.
-- (On Forever form damage IS based on weapon DPS, so Forever leaves the 4.0 default.)
function Era.StatWeightOverrides()
	return {
		DRUID = { MELEE_DPS = 0, MELEE_HIT = 0 },
	}
end

-- CLASSIC ERA: C_Item.GetItemStats does not exist and C_TooltipInfo is a nil global
-- (verified in-game 1.15.9), so there is no tooltip data to parse - every stat,
-- including the weapon DPS and armour pseudo-stats, comes from the legacy
-- GetItemStats(link) global: { ITEM_MOD_*_SHORT = n, RESISTANCE0_NAME = armour }.
-- Observed: GetItemStats(worn bow) -> { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2.38 }.
-- An uncached item returns an empty table -> nil here (caller treats as not loaded).
--
-- BUT: GetItemStats does NOT report the stats a random suffix adds ("of the Owl":
-- +Int/+Spirit came back as nothing, so a cloth belt of the Owl scored armour only,
-- seen in-game 2026-11-26 on a hunter). Those lines are only in the rendered tooltip,
-- so a hidden scanning tooltip (SetHyperlink) is read with the same line parser the
-- other flavour uses, and whatever the API missed is merged in.
--
-- AND: Classic's GetItemStats reports attack power in ITEM-BUDGET units, not the
-- number the tooltip prints. The item stat budget values 1 point = 1 Str = 1 Agi =
-- 2 AP, and the API hands back the budget point: Carving Knife of Power "+2 Attack
-- Power" -> ITEM_MOD_ATTACK_POWER_SHORT = 1 (in-game 2026-11-26; owner research).
-- Multiply by 2 to get the displayed AP, which is what the stat weights are tuned
-- against (HUNTER ATTACK_POWER = 1.0 means one displayed AP, not one budget point).
-- The tooltip scan, when it has the line, already carries the displayed number and
-- wins over the API for these keys so the two sources agree.
Era.AP_BUDGET_SCALE = 2
Era.BUDGET_SCALED_KEYS = {
	ATTACK_POWER = Era.AP_BUDGET_SCALE,
	RANGED_ATTACK_POWER = Era.AP_BUDGET_SCALE,
	FERAL_ATTACK_POWER = Era.AP_BUDGET_SCALE,
}

local scanTooltip
local SCAN_NAME = "QuestAutomatorEraScanTooltip"

local function ScanTooltipLines(link)
	if type(CreateFrame) ~= "function" then return nil end
	if not scanTooltip then
		-- No GameTooltipTemplate: the template wires shopping tooltips (the "Currently
		-- Equipped" compare), and a template scan tooltip steals/hides them from the
		-- real GameTooltip mid-hover. Plain GameTooltip + hand-made font strings.
		local ok, tt = pcall(CreateFrame, "GameTooltip", SCAN_NAME, nil)
		if not ok or type(tt) ~= "table" then return nil end
		for i = 1, 30 do
			local left = tt:CreateFontString(SCAN_NAME .. "TextLeft" .. i, "ARTWORK", "GameTooltipText")
			local right = tt:CreateFontString(SCAN_NAME .. "TextRight" .. i, "ARTWORK", "GameTooltipText")
			tt:AddFontStrings(left, right)
		end
		if tt.SetScript then pcall(tt.SetScript, tt, "OnTooltipAddMoney", nil) end
		scanTooltip = tt
	end
	local okOwner = pcall(scanTooltip.SetOwner, scanTooltip, WorldFrame or UIParent, "ANCHOR_NONE")
	if not okOwner then return nil end
	pcall(scanTooltip.ClearLines, scanTooltip)
	local okLink = pcall(scanTooltip.SetHyperlink, scanTooltip, link)
	if not okLink then return nil end
	local lines = {}
	local okN, n = pcall(scanTooltip.NumLines, scanTooltip)
	n = okN and NS.SafeNumber(n) or 0
	local function Text(region)
		if not region or type(region.GetText) ~= "function" then return nil end
		local ok, text = pcall(region.GetText, region)
		return ok and NS.SafeString(text) or nil
	end
	-- ClearLines resets the count but does NOT blank hand-added font strings, so a
	-- right-column text from the previous item ("Speed 1.60") survives into this one
	-- (seen in-game: a 2.80 staff read as 1.6). Only the first NumLines() rows are
	-- this item's; everything is read, then every string is wiped for the next scan.
	for i = 1, n do
		lines[#lines + 1] = { leftText = Text(_G[SCAN_NAME .. "TextLeft" .. i]), rightText = Text(_G[SCAN_NAME .. "TextRight" .. i]) }
	end
	for i = 1, 30 do
		local l, r = _G[SCAN_NAME .. "TextLeft" .. i], _G[SCAN_NAME .. "TextRight" .. i]
		if l then pcall(l.SetText, l, nil) end
		if r then pcall(r.SetText, r, nil) end
	end
	pcall(scanTooltip.Hide, scanTooltip)
	return { lines = lines }
end

function Era.ItemStats(link)
	if not link then return nil end
	local stats, fromTooltip = Era.ItemStatsSources(link)
	if not stats then return NS.Rewards and NS.Rewards.DeriveWeaponStats(fromTooltip) or fromTooltip end
	-- API values are budget points for the AP family: scale to displayed AP first.
	for key, scale in pairs(Era.BUDGET_SCALED_KEYS) do
		if type(stats[key]) == "number" then stats[key] = stats[key] * scale end
	end
	-- The tooltip prints displayed numbers: it fills gaps everywhere and, for the
	-- scaled keys, is trusted over the (now scaled) API if both are present.
	for key, amount in pairs(fromTooltip or {}) do
		if stats[key] == nil or Era.BUDGET_SCALED_KEYS[key] then
			stats[key] = amount
		end
	end
	return NS.Rewards and NS.Rewards.DeriveWeaponStats(stats) or stats
end

-- Debug: the raw tables each source produced for a link, before merging, so a wrong
-- number can be pinned on the API, the scan, or the merge.  /qam itemstats <link>
function Era.DumpItemStats(link)
	local api, scan = Era.ItemStatsSources(link)
	local raw = NS.Call("GetItemStats", link)
	NS.Print("GetItemStats raw:")
	for k, v in pairs(type(raw) == "table" and raw or {}) do NS.Print("  %s = %s", tostring(k), tostring(v)) end
	NS.Print("normalised API: %s", api and table.concat((function() local t = {} for k, v in pairs(api) do t[#t + 1] = k .. "=" .. tostring(v) end table.sort(t) return t end)(), ", ") or "nil")
	NS.Print("tooltip scan:   %s", scan and table.concat((function() local t = {} for k, v in pairs(scan) do t[#t + 1] = k .. "=" .. tostring(v) end table.sort(t) return t end)(), ", ") or "nil")
	local merged = Era.ItemStats(link)
	NS.Print("merged:         %s", merged and table.concat((function() local t = {} for k, v in pairs(merged) do t[#t + 1] = k .. "=" .. tostring(v) end table.sort(t) return t end)(), ", ") or "nil")
	local lines = ScanTooltipLines(link)
	for i, l in ipairs(lines and lines.lines or {}) do NS.Print("  line %d: [%s] [%s]", i, tostring(l.leftText), tostring(l.rightText)) end
end

function Era.ItemStatsSources(link)
	local stats = Client.NormalizeItemStats(NS.Call("GetItemStats", link))
	-- The scan is a bonus; if it ever throws, the API stats alone must still come back
	-- (an error here propagated through Tooltip.Describe and silenced every tooltip).
	local fromTooltip
	local okScan, result = pcall(function()
		return NS.Rewards and NS.Rewards.StatsFromTooltipData(ScanTooltipLines(link))
	end)
	if okScan then
		fromTooltip = result
	else
		NS.WarnOnce("era-scan", "item scan: " .. tostring(result))
	end
	return stats, fromTooltip
end

function Era.DebugReport()
	local E = Enum and Enum.QuestFrequency or {}
	NS.Print("Client: Classic Era; Enum.QuestFrequency Default=%s Daily=%s Weekly=%s | LE_QUEST_FREQUENCY DEFAULT=%s DAILY=%s WEEKLY=%s",
		tostring(E.Default), tostring(E.Daily), tostring(E.Weekly),
		tostring(LE_QUEST_FREQUENCY_DEFAULT), tostring(LE_QUEST_FREQUENCY_DAILY), tostring(LE_QUEST_FREQUENCY_WEEKLY))
end