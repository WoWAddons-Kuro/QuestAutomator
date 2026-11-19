-- Saved pre-pick model: no frames, quest API calls, scoring, timers, or execution.
local ADDON, NS = ...
local PrePickModel = {}
NS.PrePickModel = PrePickModel

---@alias QuestAutomator_QuestID integer
---@alias QuestAutomator_RewardItemID integer
---@alias QuestAutomator_RewardChoiceIndex integer
---@alias QuestAutomator_PrePickRevision integer
---@alias QuestAutomator_RewardLootKind integer WoW loot discriminator; Rewards.LOOT_ITEM identifies items.
---@alias QuestAutomator_RewardItemDataLoaded boolean Whether item data is available.
---@alias QuestAutomator_PrePickSelectionCount integer
---@alias QuestAutomator_PrePickResolutionStatus 'none'|'matched'|'pending'|'unavailable'|'ambiguous'
---@class QuestAutomator_RewardChoice
---@field index QuestAutomator_RewardChoiceIndex
---@field itemID QuestAutomator_RewardItemID?
---@field lootType QuestAutomator_RewardLootKind
---@field loaded QuestAutomator_RewardItemDataLoaded? True only once item data is available.
---@class QuestAutomator_PrePickResolution
---@field status QuestAutomator_PrePickResolutionStatus
---@field rewardItemID QuestAutomator_RewardItemID?
---@field rewardChoiceIndex QuestAutomator_RewardChoiceIndex?
---@field choice QuestAutomator_RewardChoice?

local selectionRevision = 0
local function IsPositiveInteger(value)
	return type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value)
end

local function SelectionStore()
	return NS.chardb and type(NS.chardb.prePicks) == "table" and NS.chardb.prePicks or nil
end

function PrePickModel.Initialize()
	if not NS.chardb then return end
	if type(NS.chardb.prePicks) ~= "table" then NS.chardb.prePicks = {} end
	for questID, rewardItemID in pairs(NS.chardb.prePicks) do
		if not IsPositiveInteger(questID) or not IsPositiveInteger(rewardItemID) then
			NS.chardb.prePicks[questID] = nil
		end
	end
	selectionRevision = selectionRevision + 1
end

---@return QuestAutomator_PrePickRevision
function PrePickModel.GetRevision() return selectionRevision end

---@return QuestAutomator_PrePickSelectionCount
function PrePickModel.GetSelectionCount()
	local count = 0
	for _ in pairs(SelectionStore() or {}) do count = count + 1 end
	return count
end

---@param questID QuestAutomator_QuestID
---@return QuestAutomator_RewardItemID?
function PrePickModel.GetSelectedRewardItemID(questID)
	if not IsPositiveInteger(questID) then return nil end
	local store = SelectionStore()
	local rewardItemID = store and store[questID]
	if IsPositiveInteger(rewardItemID) then return rewardItemID end
end

---@param questID QuestAutomator_QuestID
---@param rewardItemID QuestAutomator_RewardItemID
---@return boolean changed
function PrePickModel.SetSelectedRewardItemID(questID, rewardItemID)
	if not IsPositiveInteger(questID) or not IsPositiveInteger(rewardItemID) then return false end
	local store = SelectionStore()
	if not store or store[questID] == rewardItemID then return false end
	store[questID] = rewardItemID
	selectionRevision = selectionRevision + 1
	return true
end

---@param questID QuestAutomator_QuestID
---@return boolean changed
function PrePickModel.ClearSelection(questID)
	if not IsPositiveInteger(questID) then return false end
	local store = SelectionStore()
	if not store or store[questID] == nil then return false end
	store[questID] = nil
	selectionRevision = selectionRevision + 1
	return true
end

---@param questID QuestAutomator_QuestID
---@param offeredChoices QuestAutomator_RewardChoice[]
---@return QuestAutomator_PrePickResolution
function PrePickModel.ResolveSelectedRewardChoice(questID, offeredChoices)
	local rewardItemID = PrePickModel.GetSelectedRewardItemID(questID)
	if not rewardItemID then return { status = "none" } end
	local matchedChoice, matches = nil, 0
	local rewardDataPending = false
	for _, choice in ipairs(offeredChoices) do
		if choice.lootType == NS.Rewards.LOOT_ITEM then
			if choice.loaded ~= true or not IsPositiveInteger(choice.itemID) or not IsPositiveInteger(choice.index) then
				rewardDataPending = true
			elseif choice.itemID == rewardItemID then
				matches = matches + 1
				matchedChoice = choice
			end
		end
	end
	if rewardDataPending then return { status = "pending", rewardItemID = rewardItemID } end
	if matches > 1 then return { status = "ambiguous", rewardItemID = rewardItemID } end
	if not matchedChoice then return { status = "unavailable", rewardItemID = rewardItemID } end
	return { status = "matched", rewardItemID = rewardItemID, rewardChoiceIndex = matchedChoice.index, choice = matchedChoice }
end

NS.RegisterEvent("ADDON_LOADED", function(name)
	if name == ADDON then PrePickModel.Initialize() end
end)
NS.RegisterEvent("QUEST_TURNED_IN", PrePickModel.ClearSelection)
NS.RegisterEvent("QUEST_REMOVED", PrePickModel.ClearSelection)