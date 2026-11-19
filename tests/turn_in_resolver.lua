-- Pure pass-through resolver tests; run from the workspace root with lua5.1.
local NS = { L = setmetatable({}, {__index = function(_, key) return key end}) }
NS.Call = function() error('resolver attempted a client API call') end
assert(loadfile('QuestAutomator/Rules.lua'))('QuestAutomator', NS)
-- The original scorer resolves localized subclass labels through these helpers.
-- Keep that existing dependency outside this unit test; do not change runtime Rules.
NS.Rules.WeaponName = function() return 'Mock weapon subclass' end
NS.Rules.ArmorName = function() return 'Mock armour subclass' end
assert(loadfile('QuestAutomator/Rewards.lua'))('QuestAutomator', NS)
NS.RegisterEvent = function() end
NS.chardb = {prePicks = {}}
assert(loadfile('QuestAutomator/Models/PrePickModel.lua'))('QuestAutomator', NS)
NS.PrePickModel.Initialize()
assert(loadfile('QuestAutomator/TurnInResolver.lua'))('QuestAutomator', NS)
local Resolver = NS.TurnInResolver
local player = {class = 'PRIEST', level = 10, weights = {INTELLECT = 1}}
local function settings(mode, quality, allowKinds)
	return {rewardMode = mode, manualQuality = quality, weapons = allowKinds, trinkets = allowKinds, fallbackToValue = true}
end
local function choices(kind, loaded)
	local result = {}
	for index = 1, 2 do
		result[index] = {index = index, itemID = 1000 + index, loaded = loaded, lootType = kind == 'currency' and 1 or 0,
			quality = 3, sellPrice = index * 100, count = 1, itemLevel = 20, usable = true,
			classID = kind == 'weapon' and NS.Rules.CLASS_WEAPON or NS.Rules.CLASS_ARMOR,
			subclassID = kind == 'weapon' and 15 or NS.Rules.ARMOR.GENERIC,
			equipLoc = kind == 'weapon' and 'INVTYPE_WEAPON' or 'INVTYPE_TRINKET', stats = {INTELLECT = index}}
	end
	return result
end
local function context(count, offered, policySettings)
	return {questID = 363, rewardChoiceCount = count, rewardChoices = offered or {}, settings = policySettings or settings('fit', -1, true), player = player}
end
local originalEvaluate = NS.Rewards.Evaluate
local evaluated = 0
NS.Rewards.Evaluate = function(...) evaluated = evaluated + 1; return originalEvaluate(...) end
for _, mode in ipairs({'fit', 'value', 'manual'}) do
	for count = 0, 1 do
		local ctx = context(count, {}, settings(mode, 3, false))
		ctx.player = nil
		local result = Resolver.Resolve(ctx)
		assert(result.action == 'submit' and result.rewardChoiceIndex == count and result.rewardDecision == nil)
		assert(Resolver.IsDecisionValid(ctx, result))
	end
end
assert(evaluated == 0, 'zero/single choices must not run scoring or need item data')
print('PASS zero/single choices preserve original behaviour across all reward modes')

local cases = 0
for _, mode in ipairs({'fit', 'value', 'manual'}) do
	for _, threshold in ipairs({-1, 3}) do
		for _, allowed in ipairs({true, false}) do
			for _, kind in ipairs({'trinket', 'weapon', 'currency'}) do
				for _, loaded in ipairs({true, false}) do
					local s = settings(mode, threshold, allowed)
					local baseline = originalEvaluate(choices(kind, loaded), s, player)
					local ctx = context(2, choices(kind, loaded), s)
					local result = Resolver.Resolve(ctx)
					local expectedAction = baseline.pending and 'wait' or (baseline.index and 'submit' or 'manual')
					assert(result.action == expectedAction and result.rewardChoiceIndex == baseline.index)
					assert(result.reason == (baseline.pending and 'pending' or baseline.reason))
					assert(Resolver.IsDecisionValid(ctx, result))
					assert(result.rewardDecision.reason == baseline.reason and result.rewardDecision.pending == baseline.pending)
					cases = cases + 1
				end
			end
		end
	end
end
assert(evaluated == cases)
print('PASS ' .. cases .. ' multi-choice parity cases: scoring, quality, kinds, currencies, manual, pending')

local validContext = context(2, choices('trinket', true))
for _, bad in ipairs({{}, {action = 'submit', reason = 'x'}, {action = 'submit', reason = 'x', rewardChoiceIndex = 0},
	{action = 'submit', reason = 'x', rewardChoiceIndex = 3}, {action = 'submit', reason = 'x', rewardChoiceIndex = 1.5},
	{action = 'submit', reason = 'x', rewardChoiceIndex = '1'}, {action = 'submit', reason = 'x', rewardChoiceIndex = math.huge},
	{action = 'submit', reason = 'x', rewardChoiceIndex = 0/0}, {action = 'oops', reason = 'x'},
	{action = 'manual', reason = 'x', rewardChoiceIndex = 1}, {action = 'wait', reason = 'x', rewardChoiceIndex = 1},
	{action = 'submit', reason = 'x', rewardChoiceIndex = 1, rewardDecision = 'broken'}}) do
	assert(not Resolver.IsDecisionValid(validContext, bad))
end
assert(not Resolver.IsDecisionValid(validContext, nil))
assert(not Resolver.IsDecisionValid(validContext, false))
assert(Resolver.IsDecisionValid(validContext, {action = 'manual', reason = 'future-rule'}))
assert(Resolver.IsDecisionValid(validContext, {action = 'wait', reason = 'future-data'}))
assert(Resolver.IsDecisionValid(validContext, {action = 'submit', reason = 'future-policy', rewardChoiceIndex = 2}))
assert(not Resolver.IsDecisionValid(context(0), {action = 'submit', reason = 'x', rewardChoiceIndex = 1}))
assert(not Resolver.IsDecisionValid(context(1), {action = 'submit', reason = 'x', rewardChoiceIndex = 0}))
assert(not Resolver.IsDecisionValid(context(2, choices('currency', true)), {action = 'submit', reason = 'x', rewardChoiceIndex = 1}))
assert(not Resolver.IsDecisionValid(context(2, choices('trinket', false)), {action = 'submit', reason = 'x', rewardChoiceIndex = 1}))
assert(Resolver.Resolve({}).action == 'manual')
assert(Resolver.Resolve(nil).action == 'manual')
assert(Resolver.Resolve(context(-1)).action == 'manual')
assert(Resolver.Resolve(context(2, {})).action == 'manual')
local ctxUnknownQuest = context(0); ctxUnknownQuest.questID = nil
assert(Resolver.Resolve(ctxUnknownQuest).action == 'submit')
local ctxBadQuest = context(0); ctxBadQuest.questID = true
assert(Resolver.Resolve(ctxBadQuest).action == 'manual')
print('PASS tagged decisions, index/type checks, malformed context and fail-closed validation')

NS.PrePickModel.SetSelectedRewardItemID(363, 1001)
local baseline = Resolver.Resolve(validContext)
assert(baseline.action == 'submit' and baseline.rewardChoiceIndex == 1 and baseline.reason == 'prepick')
assert(Resolver.IsDecisionValid(validContext, baseline))
validContext.settings.tier1Action = 'auto'
validContext.settings.valueSource = 'auction'
validContext.settings.weaponProficiency = 'usable'
local unchanged = Resolver.Resolve(validContext)
assert(unchanged.action == baseline.action and unchanged.rewardChoiceIndex == baseline.rewardChoiceIndex and unchanged.reason == baseline.reason)
local reordered = choices('trinket', true)
reordered[1], reordered[2] = reordered[2], reordered[1]
reordered[1].index, reordered[2].index = 1, 2
local reorderedContext = context(2, reordered, settings('manual', 3, false))
local picked = Resolver.Resolve(reorderedContext)
assert(picked.action == 'submit' and picked.rewardChoiceIndex == 2 and picked.prePickStatus == 'matched')
assert(Resolver.IsDecisionValid(reorderedContext, picked))
local loading = Resolver.Resolve(context(2, choices('trinket', false), settings('manual', 3, false)))
assert(loading.action == 'wait' and loading.rewardChoiceIndex == nil and loading.prePickStatus == 'pending')
NS.PrePickModel.SetSelectedRewardItemID(363, 99999)
local unavailable = Resolver.Resolve(validContext)
assert(unavailable.reason ~= 'prepick' and unavailable.prePickStatus == 'unavailable')
assert(NS.PrePickModel.GetSelectedRewardItemID(363) == 99999)
NS.PrePickModel.ClearSelection(363)
print('PASS pre-pick precedence, item-ID reordering, loading, unavailable fallback and inert placeholders')