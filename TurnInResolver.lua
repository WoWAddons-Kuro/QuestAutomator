-- Turn-in policy: resolve a saved item-ID preference, otherwise delegate to the
-- original reward rules. No direct WoW calls, timers, UI, or hand-in execution.
local ADDON, NS = ...
local TurnInResolver = {}
NS.TurnInResolver = TurnInResolver

---@alias QuestAutomator_RewardChoiceCount integer
---@alias QuestAutomator_RewardChoiceIndexOrNone integer 0 means no choice; otherwise a current offered index.
---@alias QuestAutomator_TurnInAction 'submit'|'manual'|'wait'
---@alias QuestAutomator_TurnInReason string Original reason key or no-choice/single-choice/resolver-invalid.
---@alias QuestAutomator_RewardPolicySettings table Original Rewards.Evaluate settings, not UI placeholders.
---@alias QuestAutomator_PlayerRewardContext table Original Rules.Player snapshot.
---@alias QuestAutomator_RewardChoiceList table Original Rewards.Gather snapshot indexed by reward choice.
---@alias QuestAutomator_OriginalRewardDecision table Original {index?, choice?, reason?, pending?} result.
---@class QuestAutomator_TurnInContext
---@field questID QuestAutomator_QuestID? Stable ID when known; never the controller's boolean sentinel.
---@field rewardChoiceCount QuestAutomator_RewardChoiceCount
---@field rewardChoices QuestAutomator_RewardChoiceList Empty for 0/1 choices in this pass-through stage.
---@field settings QuestAutomator_RewardPolicySettings
---@field player QuestAutomator_PlayerRewardContext? Not needed for 0/1 choices.
---@class QuestAutomator_TurnInDecision
---@field action QuestAutomator_TurnInAction
---@field rewardChoiceIndex QuestAutomator_RewardChoiceIndexOrNone? Present only for submit.
---@field reason QuestAutomator_TurnInReason
---@field rewardDecision QuestAutomator_OriginalRewardDecision? Explanation/choice detail, never an action.
---@field prePickStatus QuestAutomator_PrePickResolutionStatus? Set when multiple choices are resolved.

local function IsNonNegativeInteger(value)
	return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function IsContextValid(context)
	if type(context) ~= "table" or not IsNonNegativeInteger(context.rewardChoiceCount) then return false end
	if type(context.settings) ~= "table" or type(context.rewardChoices) ~= "table" then return false end
	if context.questID ~= nil and (not IsNonNegativeInteger(context.questID) or context.questID == 0) then return false end
	if context.rewardChoiceCount > 1 then
		if type(context.player) ~= "table" or #context.rewardChoices ~= context.rewardChoiceCount then return false end
	end
	return true
end

---@param context QuestAutomator_TurnInContext
---@param decision QuestAutomator_TurnInDecision
---@return boolean valid
function TurnInResolver.IsDecisionValid(context, decision)
	if not IsContextValid(context) or type(decision) ~= "table" then return false end
	if type(decision.reason) ~= "string" or decision.reason == "" then return false end
	local detail = decision.rewardDecision
	if detail ~= nil and type(detail) ~= "table" then return false end
	if decision.action == "manual" or decision.action == "wait" then
		-- Detail may contain a recommendation; only the tagged action authorizes submission.
		return decision.rewardChoiceIndex == nil
	end
	if decision.action ~= "submit" then return false end
	local rewardChoiceIndex = decision.rewardChoiceIndex
	if not IsNonNegativeInteger(rewardChoiceIndex) then return false end
	if context.rewardChoiceCount <= 1 then
		return rewardChoiceIndex == context.rewardChoiceCount and detail == nil
	end
	if rewardChoiceIndex == 0 or rewardChoiceIndex > context.rewardChoiceCount then return false end
	local offeredChoice = context.rewardChoices[rewardChoiceIndex]
	if type(offeredChoice) ~= "table" or offeredChoice.index ~= rewardChoiceIndex then return false end
	if offeredChoice.lootType ~= NS.Rewards.LOOT_ITEM or offeredChoice.loaded ~= true then return false end
	if detail and (detail.pending or detail.index ~= rewardChoiceIndex or detail.choice ~= offeredChoice) then return false end
	return true
end

---@param context QuestAutomator_TurnInContext
---@return QuestAutomator_TurnInDecision
function TurnInResolver.Resolve(context)
	if not IsContextValid(context) then return { action = "manual", reason = "resolver-invalid" } end
	local rewardChoiceCount = context.rewardChoiceCount
	-- Preserve original zero/single-choice behaviour, even under rewardMode=manual.
	-- These are policy decisions here now; the dialog controller no longer bypasses us.
	if rewardChoiceCount == 0 then
		return { action = "submit", rewardChoiceIndex = 0, reason = "no-choice" }
	end
	if rewardChoiceCount == 1 then
		return { action = "submit", rewardChoiceIndex = 1, reason = "single-choice" }
	end
	local selection = NS.PrePickModel.ResolveSelectedRewardChoice(context.questID, context.rewardChoices)
	if selection.status == "matched" then
		local detail = { index = selection.rewardChoiceIndex, choice = selection.choice, reason = "prepick" }
		return { action = "submit", rewardChoiceIndex = selection.rewardChoiceIndex, reason = "prepick", rewardDecision = detail, prePickStatus = selection.status }
	end
	if selection.status == "pending" then
		return { action = "wait", reason = "pending", prePickStatus = selection.status }
	end
	-- No usable saved match: delegate unchanged to the original reward rules.
	local original = NS.Rewards.Evaluate(context.rewardChoices, context.settings, context.player)
	if original.pending then
		return { action = "wait", reason = "pending", rewardDecision = original, prePickStatus = selection.status }
	end
	if original.index then
		return { action = "submit", rewardChoiceIndex = original.index, reason = original.reason, rewardDecision = original, prePickStatus = selection.status }
	end
	return { action = "manual", reason = original.reason, rewardDecision = original, prePickStatus = selection.status }
end