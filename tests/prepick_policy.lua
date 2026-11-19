-- Pure model/policy tests: no frames, timers, or WoW API calls permitted.
-- Run from workspace root: lua5.1 QuestAutomator/tests/prepick_policy.lua
local handlers = {}
local NS = {
	L = setmetatable({}, {__index = function(_, key) return key end}),
	chardb = {prePicks = {[101] = 5191, [-1] = 10399, [202] = 'bad'}},
	RegisterEvent = function(event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end,
	Call = function() error('model/policy attempted a client API call') end,
}
assert(loadfile('QuestAutomator/Rules.lua'))('QuestAutomator', NS)
assert(loadfile('QuestAutomator/Rewards.lua'))('QuestAutomator', NS)
assert(loadfile('QuestAutomator/Models/PrePickModel.lua'))('QuestAutomator', NS)
assert(loadfile('QuestAutomator/TurnInResolver.lua'))('QuestAutomator', NS)
local Model = NS.PrePickModel
-- Project the production resolver's tagged result for these model/policy assertions.
local Policy = { Evaluate = function(questID, offeredChoices, settings, player)
	local ctx = {questID = questID, rewardChoiceCount = #offeredChoices, rewardChoices = offeredChoices, settings = settings, player = player}
	local result = NS.TurnInResolver.Resolve(ctx)
	assert(NS.TurnInResolver.IsDecisionValid(ctx, result))
	return {index = result.rewardChoiceIndex, choice = result.rewardDecision and result.rewardDecision.choice,
		reason = result.reason, pending = result.action == 'wait' or nil, prePickStatus = result.prePickStatus}
end }
local function emit(event, ...) for _, fn in ipairs(handlers[event] or {}) do fn(...) end end
emit('ADDON_LOADED', 'QuestAutomator')
assert(Model.GetSelectedRewardItemID(101) == 5191)
assert(NS.chardb.prePicks[-1] == nil and NS.chardb.prePicks[202] == nil)
local revision = Model.GetRevision()
assert(not Model.SetSelectedRewardItemID(-1, 5191))
assert(not Model.SetSelectedRewardItemID(true, 5191))
assert(not Model.SetSelectedRewardItemID('101', 5191))
assert(not Model.SetSelectedRewardItemID(101, 0))
assert(not Model.SetSelectedRewardItemID(101, 1.5))
assert(not Model.SetSelectedRewardItemID(101, math.huge))
assert(not Model.SetSelectedRewardItemID(101, 0/0))
assert(not Model.SetSelectedRewardItemID(101, 5191))
assert(Model.GetRevision() == revision)
assert(Model.SetSelectedRewardItemID(202, 10399))
assert(Model.GetRevision() == revision + 1)
assert(Model.GetSelectedRewardItemID(101) == 5191)
Model.Initialize()
assert(Model.GetSelectedRewardItemID(202) == 10399)
print('PASS validation, persistence, per-quest isolation, revision and sample-ID rejection')

local function choice(rewardChoiceIndex, rewardItemID, loaded, lootType)
	return { index = rewardChoiceIndex, itemID = rewardItemID, loaded = loaded, lootType = lootType or 0,
		quality = 3, sellPrice = rewardItemID == 10399 and 200 or 100, count = 1, stats = {}, usable = true,
		classID = NS.Rules.CLASS_ARMOR, subclassID = NS.Rules.ARMOR.GENERIC, equipLoc = 'INVTYPE_TRINKET', itemLevel = 20 }
end
local function offered() return {choice(1, 10399, true), choice(2, 5191, true)} end
local result = Model.ResolveSelectedRewardChoice(101, offered())
assert(result.status == 'matched' and result.rewardChoiceIndex == 2 and result.rewardItemID == 5191)
assert(Model.ResolveSelectedRewardChoice(202, offered()).rewardChoiceIndex == 1)
assert(Model.ResolveSelectedRewardChoice(303, offered()).status == 'none')
assert(Model.ResolveSelectedRewardChoice(101, {choice(1, 10399, true)}).status == 'unavailable')
assert(Model.ResolveSelectedRewardChoice(101, {}).status == 'unavailable')
assert(Model.ResolveSelectedRewardChoice(101, {choice(1, 5191, true, 1)}).status == 'unavailable')
assert(Model.ResolveSelectedRewardChoice(101, {choice(1, 5191, true), choice(2, 5191, true)}).status == 'ambiguous')
assert(Model.ResolveSelectedRewardChoice(101, {choice(1, 5191, false)}).status == 'pending')
assert(Model.ResolveSelectedRewardChoice(101, {choice(1, 5191, nil)}).status == 'pending')
assert(Model.ResolveSelectedRewardChoice(101, {choice(1, 5191, true), choice(2, nil, false)}).status == 'pending')
assert(Model.ResolveSelectedRewardChoice(101, {choice(0, 5191, true)}).status == 'pending')
print('PASS reordered indices, missing/currency/duplicate choices, unknown and unloaded data')

local originalEvaluate, evaluations = NS.Rewards.Evaluate, 0
NS.Rewards.Evaluate = function(...) evaluations = evaluations + 1; return originalEvaluate(...) end
local player = {class = 'PRIEST', level = 10, weights = {INTELLECT = 1}}
local manual = {rewardMode = 'manual', manualQuality = 3, weapons = false, trinkets = false}
local decision = Policy.Evaluate(101, offered(), manual, player)
assert(decision.index == 2 and decision.choice.itemID == 5191 and decision.reason == 'prepick')
assert(decision.prePickStatus == 'matched' and evaluations == 0)
decision = Policy.Evaluate(101, {choice(1, 5191, false), choice(2, 10399, true)}, manual, player)
assert(decision.pending and not decision.index and evaluations == 0)
decision = Policy.Evaluate(101, {choice(1, 10399, true), choice(2, 10400, true)}, manual, player)
assert(not decision.index and decision.reason == 'manual' and decision.prePickStatus == 'unavailable' and evaluations == 1)
assert(Model.GetSelectedRewardItemID(101) == 5191, 'snapshot must not discard stored selection')
decision = Policy.Evaluate(nil, offered(), manual, player)
assert(decision.reason == 'manual' and decision.prePickStatus == 'none' and evaluations == 2)
local quality = {rewardMode = 'fit', manualQuality = 3, weapons = false, trinkets = false}
assert(Policy.Evaluate(101, offered(), quality, player).reason == 'prepick')
assert(Policy.Evaluate(303, offered(), quality, player).reason == 'quality')
local value = {rewardMode = 'value', manualQuality = -1, weapons = true, trinkets = true}
decision = Policy.Evaluate(303, offered(), value, player)
assert(decision.choice.itemID == 10399 and decision.prePickStatus == 'none')
decision = Policy.Evaluate(101, {choice(1, 10399, true), choice(2, 10400, true)}, value, player)
assert(decision.choice.itemID == 10399 and decision.prePickStatus == 'unavailable')
decision = Policy.Evaluate(101, {choice(1, 5191, true), choice(2, 5191, true)}, value, player)
assert(decision.reason == 'value' and decision.prePickStatus == 'ambiguous')
print('PASS explicit-pick precedence, pending without guessing, original fallback, preview and quality/manual modes')

-- No pick must preserve original scoring across original modes and reward gates.
local function settings(mode, weapons, trinkets, threshold, fallback)
	return {rewardMode = mode, weapons = weapons, trinkets = trinkets, manualQuality = threshold, fallbackToValue = fallback}
end
for _, mode in ipairs({'fit', 'value', 'manual'}) do
	for _, allow in ipairs({true, false}) do
		local s = settings(mode, allow, allow, -1, true)
		local baseline = originalEvaluate(offered(), s, player)
		local actual = Policy.Evaluate(303, offered(), s, player)
		assert(actual.index == baseline.index and actual.reason == baseline.reason and actual.pending == baseline.pending)
	end
end
print('PASS no-selection parity with original policy')

emit('QUEST_TURNED_IN', 101, 40, 0)
assert(Model.GetSelectedRewardItemID(101) == nil and Model.GetSelectedRewardItemID(202) == 10399)
emit('QUEST_REMOVED', 202)
assert(Model.GetSelectedRewardItemID(202) == nil)
assert(not Model.ClearSelection(202))
print('PASS cleanup on actual hand-in/abandon, isolated by quest')