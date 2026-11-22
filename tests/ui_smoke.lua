-- Run from workspace root: lua5.1 QuestAutomator/tests/ui_smoke.lua era [zhCN]
-- This is a mock UI/API test, not proof of in-game client behaviour.
local modern = arg[1] == "forever"
local locale = arg[2] or "enUS"
local frames, timers, messages = {}, {}, {}
local now, selectedLogIndex, selectedQuestID = 100, 2, 101
local questRows = { { questID = 101, title = "First quest" }, { questID = 202, title = "Second quest" } }
local questItems = { [101] = {5191, 10399}, [202] = {19024, 5191} }
local cacheReady, questChoiceCount, rewardCalls, accepted = true, 0, {}, 0
local offerItems = {5191, 10399}
local methods = {}
local function noop() end
local function region(parent, name)
	local r = { parent = parent, name = name, children = {}, scripts = {}, shown = true, width = 100, height = 20, text = "" }
	setmetatable(r, { __index = methods })
	if name then _G[name] = r end
	return r
end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:HookScript(event, fn) local old = self.scripts[event]; self.scripts[event] = function(...) if old then old(...) end; fn(...) end end
function methods:GetChildren() return unpack(self.children) end
function methods:GetName() return self.name end
function methods:GetParent() return self.parent end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetText(t) self.text = t or "" end
function methods:GetText() return self.text end
local fontScale = 1
local function printableWidth(text)
	text = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
	return #text * 5 * fontScale
end
function methods:GetStringWidth() return printableWidth(self.text) end
function methods:GetStringHeight() return math.max(1, math.ceil(printableWidth(self.text) / math.max(1, self.width))) * 12 * fontScale end
function methods:SetHitRectInsets(...) self.hitRectInsets = {...} end
function methods:SetPoint(...) self.point = {...} end
function methods:GetPoint() return unpack(self.point or {"CENTER", nil, "CENTER", 0, 0}) end
function methods:ClearAllPoints() self.point = nil end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetValue(value) self.value = value; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end end
function methods:GetValue() return self.value end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:GetVerticalScrollRange() return 2000 end
function methods:GetTop() return 1000 end
function methods:GetBottom() return 0 end
function methods:GetCenter() return 400, 400 end
function methods:GetEffectiveScale() return 1 end
function methods:GetFrameLevel() return 1 end
function methods:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetShown(show) if show then self:Show() else self:Hide() end end
function methods:CreateTexture() return region(self) end
function methods:CreateFontString() return region(self) end
function methods:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end
function methods:AddDoubleLine(a, b) self:AddLine(a .. " " .. b) end
function methods:SetOwner() self.lines = {} end
for _, method in ipairs({"RegisterEvent", "SetAllPoints", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetFrameStrata", "SetFrameLevel", "SetMovable", "EnableMouse", "RegisterForDrag", "SetClampedToScreen", "SetJustifyH", "SetWordWrap", "SetTextColor", "RegisterForClicks", "SetTexCoord", "SetTexture", "SetColorTexture", "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag", "EnableMouseWheel", "SetScrollChild", "StartMoving", "StopMovingOrSizing", "SetHighlightTexture", "SetDesaturated", "SetVertexColor", "SetHyperlink", "SetItemByID", "SetBlendMode", "SetAutoFocus", "SetNumeric", "SetMaxLetters", "ClearFocus"}) do methods[method] = noop end
function CreateFrame(kind, name, parent, template)
	local f = region(parent, name)
	frames[#frames + 1] = f
	if parent then parent.children[#parent.children + 1] = f end
	if template == "InterfaceOptionsCheckButtonTemplate" then f.Text = region(f) end
	if template == "OptionsSliderTemplate" then
		region(f, name .. "Low"); region(f, name .. "High"); region(f, name .. "Text")
	end
	return f
end
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap", UIParent)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
BackdropTemplateMixin = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = {delay = delay, fn = fn} end }
GetTime = function() return now end
time = function() return 1000 end
date = os.date
local function drain()
	local count = 0
	while #timers > 0 do
		count = count + 1; assert(count < 100, "timer loop")
		local timer = table.remove(timers, 1); now = now + timer.delay; timer.fn()
	end
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList = {}
GetLocale = function() return locale end
UnitName = function() return "Tester" end
GetRealmName = function() return "Test realm" end
UnitClassBase = function() return "PRIEST" end
UnitClass = function() return "Priest", "PRIEST" end
UnitLevel = function() return 10 end
UnitGUID = function() return "Creature-0-1-1-1-123-1" end
IsShiftKeyDown = function() return false end
IsAltKeyDown = IsShiftKeyDown
IsControlKeyDown = IsShiftKeyDown
GetBuildInfo = function() return "mock", "mock", "mock", modern and 16001 or 11509 end
-- Flavour selection (Client/Client_Select.lua) keys off WOW_PROJECT_ID == WOW_PROJECT_CLASSIC.
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC = 1, 2
WOW_PROJECT_ID = modern and WOW_PROJECT_MAINLINE or WOW_PROJECT_CLASSIC
GetQuestID = function() return 363 end
GetTitleText = function() return "Rude Awakening" end
QuestFlagsPVP = function() return false end
QuestGetAutoAccept = function() return false end
AcceptQuest = function() accepted = accepted + 1 end
GetQuestMoneyToGet = function() return 0 end
IsQuestCompletable = function() return true end
GetNumQuestChoices = function() return questChoiceCount end
GetQuestReward = function(index) rewardCalls[#rewardCalls + 1] = index end
GetMaxPlayerLevel = function() return 60 end
UnitXP = function() return 0 end
UnitXPMax = function() return 400 end
GetNumQuestLogEntries = function() return #questRows end
GetQuestLogTitle = function(index)
	local q = questRows[index]
	if q then return q.title, 1, nil, false, false, nil, 1, q.questID end
end
GetQuestLogIndexByID = function(id) for index, q in ipairs(questRows) do if q.questID == id then return index end end; return 0 end
GetQuestLogSelection = function() return selectedLogIndex end
SelectQuestLogEntry = function(index) selectedLogIndex = index end
GetQuestLogSelectedID = function() local q = questRows[selectedLogIndex]; return q and q.questID or 0 end
local function rewardQuestID(id) return modern and id or GetQuestLogSelectedID() end
GetNumQuestLogChoices = function(id) return #(questItems[rewardQuestID(id)] or {}) end
local function item(id)
	if not cacheReady then return nil end
	local names = {[5191] = "Cruel Barb", [10399] = "Blackened Defias Armor", [19024] = "Arena Grand Master"}
	return names[id], "item:" .. id, 3, 22, 1, nil, nil, 1, "INVTYPE_TRINKET", 123, 100
end
C_Item = {
	GetItemInfo = function(ref) return item(tonumber(tostring(ref):match("%d+"))) end,
	GetItemInfoInstant = function(ref) return tonumber(tostring(ref):match("%d+")), nil, nil, "INVTYPE_TRINKET", 123, 4, 0 end,
	GetItemStats = function() return {ITEM_MOD_INTELLECT_SHORT = 5} end,
	RequestLoadItemDataByID = noop,
}
GetInventoryItemLink = function() return "item:5191" end
GetQuestLogChoiceInfo = function(index, id)
	local itemID = (questItems[rewardQuestID(id)] or {})[index]
	if itemID then local name = item(itemID); return name, 123, 1, 3, true, itemID end
end
GetQuestLogItemLink = function(_, index) return "item:" .. questItems[GetQuestLogSelectedID()][index] end
GetQuestItemInfoLootType = function() return 0 end
GetQuestItemInfo = function(_, index)
	local id = offerItems[index]
	if modern then return item(id), 123, 1, 3, true, id end
	return item(id), 123, 1, 3, true -- Era: identity must be recovered from the item link.
end
GetQuestItemLink = function(_, index) return "item:" .. offerItems[index] end
C_TooltipInfo = { GetHyperlink = function() return {lines = {{leftText = "+5 Intellect"}}} end }
C_TooltipInfo.GetQuestItem = C_TooltipInfo.GetHyperlink
C_QuestLog = { IsOnQuest = function() return false end }
if modern then
	C_QuestLog.GetSelectedQuest = function() return selectedQuestID end
	C_QuestLog.GetNumQuestLogEntries = GetNumQuestLogEntries
	C_QuestLog.GetInfo = function(index) return questRows[index] end
end
C_AddOns = { GetAddOnMetadata = function() return "mock-ui-baseline" end }
local openedSettings = 0
Settings = {
	RegisterCanvasLayoutCategory = function() return {GetID = function() return 1 end} end,
	RegisterAddOnCategory = noop,
	OpenToCategory = function() openedSettings = openedSettings + 1 end,
}
hooksecurefunc = noop

local NS = {}
for line in io.lines("QuestAutomator/QuestAutomator.toc") do
	line = line:gsub("\r", "")
	if line ~= "" and line:sub(1, 1) ~= "#" then
		assert(loadfile("QuestAutomator/" .. line:gsub("\\", "/")))("QuestAutomator", NS)
	end
end
local function emit(event, ...)
	for _, handler in ipairs(NS.handlers[event] or {}) do handler(...) end
	assert(not next(NS.eventErrors), "event handler errors")
end
emit("ADDON_LOADED", "QuestAutomator")
emit("PLAYER_LOGIN")
drain()
assert(NS.loaded and NS.settingsCategory and not NS.Engine)
assert(NS.Client and NS.Client.flavour == (modern and "forever" or "classic_era"), "wrong client flavour selected")
for _, name in ipairs(NS.Client.INTERFACE) do assert(type(NS.Client[name]) == "function", "client interface missing " .. name) end
assert(NS.db.settings.tier2Action == "upgrade" and NS.db.settings.tier5Action == "cash" and NS.db.settings.upgradeBand == 5 and type(NS.chardb.prePicks) == "table")
assert(SlashCmdList.QUESTAUTOMATOR and not SlashCmdList.SMARTQUESTAUTOMATION)
assert(NS.RegisterSettings())
QuestAutomatorOptions:Show(); QuestAutomatorOptions:Update()
assert(#messages == 0, table.concat(messages, "\n"))
print("PASS TOC load, settings construction/update, defaults, and original module boundaries")

-- Test the actual settings widgets, not just the pure flow helper, under width
-- and text-size changes. Geometry metadata and frame anchors must agree.
local beforeSettings = {}
for key, value in pairs(NS.db.settings) do beforeSettings[key] = value end
local rowsChecked = 0
local function checkRows(entries, owner, leftInset)
	local previousBottom = 0
	for _, entry in ipairs(entries) do
		local widget = entry.widget
		assert(entry.y >= previousBottom and entry.x >= 0)
		assert(widget:GetHeight() == entry.height and widget:GetWidth() == entry.width)
		assert(leftInset + entry.x + entry.width <= owner:GetWidth())
		assert(widget.point[1] == 'TOPLEFT' and widget.point[2] == owner)
		assert(widget.point[4] == leftInset + entry.x and widget.point[5] == -entry.y)
		if widget.rows then checkRows(widget.rows, widget, 10) end
		if widget.checkbox then assert(6 + widget.label:GetStringHeight() <= entry.height) end
		if type(widget.text) == 'table' then assert(widget.text:GetStringHeight() <= entry.height) end
		if widget.optionLayout then
			assert(widget.optionsY + widget.optionLayout.height <= entry.height)
			if widget.optionsX == 24 then assert(widget.optionsY >= 2 + widget.label:GetStringHeight() + 8) end
			for _, cell in ipairs(widget.optionLayout.cells) do
				assert(widget.optionsX + cell.x + cell.width <= entry.width)
				assert(widget.optionsY + cell.y + cell.height <= entry.height)
			end
		end
		previousBottom = entry.y + entry.height
		assert(previousBottom <= owner:GetHeight())
		rowsChecked = rowsChecked + 1
	end
end
for _, scale in ipairs({1, 1.4}) do
	fontScale = scale
	for _, width in ipairs({360, 480, 620, 900}) do
		QuestAutomatorOptions.scroll:SetWidth(width)
		QuestAutomatorOptions.scroll.scripts.OnSizeChanged(QuestAutomatorOptions.scroll, width)
		QuestAutomatorOptions:Update()
		assert(QuestAutomatorOptions.content:GetWidth() == width)
		checkRows(QuestAutomatorOptions.layoutRows, QuestAutomatorOptions.content, 16)
	end
end
for key, value in pairs(beforeSettings) do assert(NS.db.settings[key] == value, 'layout changed setting ' .. key) end
fontScale = 1
QuestAutomatorOptions.scroll:SetWidth(620); QuestAutomatorOptions:Update()
print('PASS measured settings layout: ' .. rowsChecked .. ' rows across widths/font sizes; no setting mutations')

local beforeIndex = selectedLogIndex
local source = NS.PrePickData.LogSource(101)
assert(source.Count() == 2)
assert(selectedLogIndex == beforeIndex)
assert(select(6, source.Info(1)) == 5191)
local sources = NS.PrePick.PendingQuests()
assert(#sources == 2 and sources[1].action == "recommend")
assert(selectedLogIndex == beforeIndex)
selectedLogIndex = 0
assert(NS.PrePickData.LogSource(101).Count() == 2 and selectedLogIndex == 0)
selectedLogIndex = beforeIndex
print("PASS UI quest enumeration and snapshot/selection restoration, including selection 0")

local button = QuestAutomatorMinimapButton
local enabled = NS.db.settings.enabled
button.scripts.OnEnter(button)
assert(#GameTooltip.lines >= 6)
button.scripts.OnClick(button, "LeftButton")
assert(QuestAutomatorPrePickFrame:IsShown() and NS.PrePick.state.questID == 101)
assert(NS.db.settings.enabled == enabled)
button.scripts.OnClick(button, "LeftButton")
assert(not QuestAutomatorPrePickFrame:IsShown() and NS.db.settings.enabled == enabled)
button.scripts.OnClick(button, "LeftButton")
assert(QuestAutomatorPrePickFrame:IsShown() and NS.PrePick.state.questID == 101)
button.scripts.OnClick(button, "RightButton")
assert(openedSettings == 1 and NS.db.settings.enabled == enabled)
local firstChoice = NS.PrePick.state.choices[1]
NS.PrePick.Choose(firstChoice)
assert(NS.PrePick.Get(101) == firstChoice.itemID)
assert(QuestAutomatorPrePickFrame:IsShown())
assert(messages[#messages]:find(string.format(NS.L["Pre-pick for %s: %s."], "First quest", NS.Rewards.ChoiceLabel(firstChoice)), 1, true))
assert(QuestAutomatorPrePickFrame.Notice.text == NS.L["Pre-select your reward."])
assert(NS.PrePick.state.decision.reason == 'prepick')
local switched = false
for _, f in ipairs(frames) do
	if f.questID == 202 and f.scripts.OnClick then f.scripts.OnClick(f); switched = true; break end
end
assert(switched and NS.PrePick.state.questID == 202)
NS.PrePick.Choose(NS.PrePick.state.choices[1])
assert(NS.PrePick.Get(202) == 19024 and NS.PrePick.Get(101) == 5191)
print("PASS minimap actions, pending quest navigation, independent pre-picks, visible safeguard notice")

NS.PrePick.Hide()
NS.db.settings.prePickUnlocked = true
NS.PrePick.SetUnlocked(true)
assert(NS.PrePick.state.preview and #NS.PrePick.state.choices == 3)
assert(NS.PrePick.state.choices[1].itemID == 5191)
NS.PrePick.Choose(NS.PrePick.state.choices[1])
assert(NS.PrePick.Get(-1) == nil)
button.scripts.OnClick(button, "LeftButton")
assert(not NS.db.settings.prePickUnlocked and not QuestAutomatorPrePickFrame:IsShown())
cacheReady = false
NS.PrePick.Open(101, true)
assert(NS.PrePick.state.decision.pending)
button.scripts.OnClick(button, "LeftButton")
cacheReady = true
drain()
assert(not QuestAutomatorPrePickFrame:IsShown(), "stale retry reopened window")
local savedRows = questRows; questRows = {}
NS.PrePick.InvalidatePending()
button.scripts.OnClick(button, "LeftButton")
assert(QuestAutomatorPrePickFrame:IsShown() and NS.PrePick.state.questID == 0)
assert(NS.db.settings.enabled == enabled)
button.scripts.OnClick(button, "LeftButton")
assert(not QuestAutomatorPrePickFrame:IsShown() and NS.db.settings.enabled == enabled)
button.scripts.OnClick(button, "LeftButton")
assert(QuestAutomatorPrePickFrame:IsShown() and NS.PrePick.state.questID == 0)
questRows = savedRows; NS.PrePick.InvalidatePending(); NS.PrePick.Hide()
print("PASS preview, loading/retry cancellation, and empty window without automation toggle")

local clickedSupported, clickedPlaceholder = false, false
for _, f in ipairs(frames) do
	if f.Text and f.Text.text == NS.L["Enable the automation"] then
		f:SetChecked(false); f.scripts.OnClick(f)
		assert(NS.db.settings.enabled == false)
		f:SetChecked(true); f.scripts.OnClick(f)
		clickedSupported = true
	elseif f.value == "usable" and f.scripts.OnClick then
		f.scripts.OnClick(f)
		assert(NS.db.settings.weaponProficiency == "usable")
		clickedPlaceholder = true
	end
end
assert(clickedSupported and clickedPlaceholder)
NS.InitDB(); NS.PrePickModel.Initialize(); NS.UIState.Initialize()
assert(NS.PrePick.Get(101) == 5191 and NS.PrePick.Get(202) == 19024)
assert(NS.db.settings.weaponProficiency == "usable")
print("PASS supported/placeholder setting callbacks and saved-state reinitialization")

-- Unsupported settings and UI storage cannot alter the original reward policy.
local choices = NS.Rewards.Gather(2)
local original = NS.Rewards.Evaluate(choices, NS.db.settings, NS.Rules.Player())
-- Tier dispositions are live settings, so leave them at their defaults here; only
-- the saved-only placeholders below are being proven inert. Setting a tier to the
-- legacy word "auto" must still be understood (it maps to that tier's old meaning).
NS.db.settings.tier3Action = 'auto'
assert(NS.UIState.MigrateTierAction(3, 'auto') == 'upgrade' and NS.UIState.MigrateTierAction(5, 'auto') == 'cash')
assert(NS.UIState.MigrateTierAction(4, 'recommend') == 'ask' and NS.UIState.MigrateTierAction(2, 'bogus') == 'upgrade')
NS.db.settings.ilvlBand = 10
NS.db.settings.weaponProficiency = 'usable'
NS.db.settings.valueSource = 'auction'
local after = NS.Rewards.Evaluate(NS.Rewards.Gather(2), NS.db.settings, NS.Rules.Player())
assert(original.index == after.index and original.reason == after.reason)
NS.PrePickModel.SetSelectedRewardItemID(363, 5191)
questChoiceCount = 2
emit('QUEST_COMPLETE'); drain()
assert(#rewardCalls == 1 and rewardCalls[1] == 1, 'valid pre-pick did not override quality recommendation gate')
assert(NS.PrePickModel.GetSelectedRewardItemID(363) == 5191, 'attempt must not clear the pick')
emit('QUEST_TURNED_IN', 363, 40, 0)
assert(NS.PrePick.Get(363) == nil and NS.PrePick.Get(101) == 5191 and NS.PrePick.Get(202) == 19024)
emit('QUEST_FINISHED')
questChoiceCount = 0
NS.Auto.EndInteraction()
emit('QUEST_COMPLETE'); drain()
assert(#rewardCalls == 2 and rewardCalls[2] == 0, 'zero-choice hand-in path changed')
emit('QUEST_DETAIL', 0); drain()
assert(accepted == 1, 'original accept path did not run')
print('PASS placeholders inert, saved pick consumed and cleared on success, zero-choice and accept paths unchanged')
print('PASS UI smoke suite: ' .. (modern and 'Forever-shaped' or 'Era-shaped') .. ' APIs, locale ' .. locale)

-- Live regression: quest 363 reports gossip isComplete=false while the legacy
-- IsQuestComplete(363) query returns true. Exercise gossip -> QUEST_COMPLETE -> reward 0.
local function checkGossipTurnIn(label, gossipComplete, completionQuery, expectedSelections, expectedRewards, configure)
	NS.Auto.EndInteraction(); NS.Auto.OnQuestFinished()
	NS.Auto.state.sessionPaused = false
	NS.db.settings.enabled, NS.db.settings.turnIn = true, true
	NS.db.settings.turnInRepeatable = false
	NS.db.ignoredQuests[363] = nil
	IsShiftKeyDown = function() return false end
	GetQuestMoneyToGet = function() return 0 end
	IsQuestComplete = completionQuery
	questChoiceCount, rewardCalls = 0, {}
	local selectedCount = 0
	local gossipQuest = { questID = 363, title = 'Rude Awakening', isComplete = gossipComplete, repeatable = false, frequency = 0 }
	C_GossipInfo = {
		GetActiveQuests = function() return {gossipQuest} end,
		GetAvailableQuests = function() return {} end,
		SelectActiveQuest = function(questID)
			assert(questID == 363, label .. ': wrong quest selected')
			selectedCount = selectedCount + 1
			emit('GOSSIP_CLOSED', true)
			emit('QUEST_COMPLETE')
		end,
	}
	if configure then configure(gossipQuest) end
	emit('GOSSIP_SHOW'); drain()
	assert(selectedCount == expectedSelections, label .. ': wrong selection count ' .. selectedCount)
	assert(#rewardCalls == expectedRewards, label .. ': wrong reward count ' .. #rewardCalls)
	if expectedRewards > 0 then assert(rewardCalls[1] == 0, label .. ': not reward 0') end
	print('PASS gossip regression: ' .. label)
end
local function complete363(questID) assert(questID == 363); return true end
checkGossipTurnIn('Rude Awakening false flag / true query', false, complete363, 1, 1)
checkGossipTurnIn('incomplete quest', false, function() return false end, 0, 0)
checkGossipTurnIn('absent legacy API', false, nil, 0, 0)
checkGossipTurnIn('existing true flag needs no fallback', true, function() error('fallback must not run') end, 1, 1)
checkGossipTurnIn('unknown completion', false, function() return nil end, 0, 0)
checkGossipTurnIn('ignored quest', false, complete363, 0, 0, function() NS.db.ignoredQuests[363] = true end)
checkGossipTurnIn('repeatable safeguard', false, complete363, 0, 0, function(q) q.repeatable = true end)
checkGossipTurnIn('master switch off', false, complete363, 0, 0, function() NS.db.settings.enabled = false end)
checkGossipTurnIn('hand-in switch off', false, complete363, 0, 0, function() NS.db.settings.turnIn = false end)
checkGossipTurnIn('session paused', false, complete363, 0, 0, function() NS.Auto.state.sessionPaused = true end)
checkGossipTurnIn('modifier held', false, complete363, 0, 0, function() IsShiftKeyDown = function() return true end end)
checkGossipTurnIn('money safeguard', false, complete363, 1, 0, function() GetQuestMoneyToGet = function() return 100 end end)

-- Resolver checkpoint: test through the existing deferred controller, not only
-- the resolver function. Pre-pick scaffolding must remain completely unloaded.
assert(NS.PrePickModel ~= nil and NS.RewardSelectionPolicy == nil)
local realResolve = NS.TurnInResolver.Resolve
local resolverCalls, itemLoadRequests = 0, 0
local function resetTurnIn(count)
	timers, rewardCalls = {}, {}
	offerItems = {5191, 10399}
	NS.PrePickModel.ClearSelection(363)
	NS.Auto.EndInteraction(); NS.Auto.OnQuestFinished()
	NS.Auto.state.sessionPaused = false
	NS.db.settings.enabled, NS.db.settings.turnIn = true, true
	NS.db.settings.rewardMode, NS.db.settings.manualQuality = 'value', -1
	NS.db.settings.trinkets, NS.db.settings.weapons = true, true
	NS.db.settings.turnInRepeatable = false
	NS.db.ignoredQuests[363], NS.db.ignoredNPCs[123] = nil, nil
	IsShiftKeyDown = function() return false end
	GetQuestMoneyToGet = function() return 0 end
	GetQuestID = function() return 363 end
	NS.Client.IsQuestRepeatable = function() return false end  -- logic sees only the Client interface
	questChoiceCount, cacheReady = count, true
	resolverCalls, itemLoadRequests = 0, 0
	C_Item.RequestLoadItemDataByID = function() itemLoadRequests = itemLoadRequests + 1 end
	NS.TurnInResolver.Resolve = function(ctx)
		resolverCalls = resolverCalls + 1
		assert(ctx.questID == 363 and ctx.rewardChoiceCount == count)
		return realResolve(ctx)
	end
end
for count = 0, 2 do
	resetTurnIn(count)
	NS.PrePickModel.SetSelectedRewardItemID(363, 10399) -- deliberately different from the automatic index-1 choice
	emit('QUEST_COMPLETE'); drain()
	assert(resolverCalls == 1 and #rewardCalls == 1 and rewardCalls[1] == count)
end
print('PASS controller routes 0/1/2 choices through resolver; multi-choice pre-pick consumed')

resetTurnIn(0)
NS.TurnInResolver.Resolve = function() return {action = 'manual', reason = 'manual'} end
emit('QUEST_COMPLETE'); drain()
assert(#rewardCalls == 0, 'zero-choice branch bypassed manual decision')
resetTurnIn(1)
NS.TurnInResolver.Resolve = function() return {action = 'manual', reason = 'manual'} end
emit('QUEST_COMPLETE'); drain()
assert(#rewardCalls == 0, 'single-choice branch bypassed manual decision')
resetTurnIn(2); NS.db.settings.rewardMode = 'manual'
emit('QUEST_COMPLETE'); drain(); assert(resolverCalls == 1 and #rewardCalls == 0)
resetTurnIn(2); NS.db.settings.manualQuality = 3
emit('QUEST_COMPLETE'); drain(); assert(resolverCalls == 1 and #rewardCalls == 0)
print('PASS manual/quality decisions remain manual; no zero/single-choice bypass of interface')

local blockedCases = {
	function() NS.db.settings.enabled = false end,
	function() NS.db.settings.turnIn = false end,
	function() NS.Auto.state.sessionPaused = true end,
	function() IsShiftKeyDown = function() return true end end,
	function() NS.db.ignoredQuests[363] = true end,
	function() NS.db.ignoredNPCs[123] = true end,
	function() NS.Client.IsQuestRepeatable = function() return true end end,
	function() GetQuestMoneyToGet = function() return 100 end end,
}
for _, block in ipairs(blockedCases) do
	resetTurnIn(2); NS.PrePickModel.SetSelectedRewardItemID(363, 10399); block(); emit('QUEST_COMPLETE'); drain()
	assert(resolverCalls == 0 and #rewardCalls == 0, 'resolver bypassed controller safeguards')
end
print('PASS eight permission safeguards run before resolver')

local function runInitialDeferredAction()
	local task = table.remove(timers, 1); assert(task); now = now + task.delay; task.fn()
end
resetTurnIn(2); cacheReady = false
emit('QUEST_COMPLETE'); runInitialDeferredAction()
assert(NS.Auto.state.pending and resolverCalls == 1 and #rewardCalls == 0 and itemLoadRequests == 2)
cacheReady = true; drain()
assert(#rewardCalls == 1 and resolverCalls == 2 and NS.Auto.state.pending == nil)
resetTurnIn(2); cacheReady = false
emit('QUEST_COMPLETE'); drain()
assert(#rewardCalls == 0 and resolverCalls == NS.Auto.MAX_LOAD_TRIES and NS.Auto.state.pending == nil)
for _, cancel in ipairs({
	function() GetQuestID = function() return 999 end end,
	function() emit('QUEST_FINISHED') end,
	function() NS.Auto.state.sessionPaused = true end,
}) do
	resetTurnIn(2); cacheReady = false
	emit('QUEST_COMPLETE'); runInitialDeferredAction(); cancel(); cacheReady = true; drain()
	assert(#rewardCalls == 0 and resolverCalls == 1 and NS.Auto.state.pending == nil)
end
print('PASS wait -> loaded submit, bounded retries, wrong-quest/closed/paused cancellation')

for _, badResolver in ipairs({
	function() error('intentional resolver test error') end,
	function() return nil end,
	function() return {action = 'invalid', reason = 'manual'} end,
	function() return {action = 'submit', reason = 'fit', rewardChoiceIndex = 999} end,
	function() return {action = 'wait', reason = 'pending', rewardChoiceIndex = 1} end,
}) do
	resetTurnIn(2); NS.TurnInResolver.Resolve = badResolver
	emit('QUEST_COMPLETE'); drain()
	assert(#rewardCalls == 0 and NS.Auto.state.pending == nil, 'invalid decision executed')
end
resetTurnIn(0)
local savedResolver = NS.TurnInResolver; NS.TurnInResolver = nil
emit('QUEST_COMPLETE'); drain(); assert(#rewardCalls == 0)
NS.TurnInResolver = savedResolver
resetTurnIn(0)
emit('QUEST_COMPLETE'); drain(); emit('QUEST_COMPLETE'); drain()
assert(#rewardCalls == 1, 'duplicate reward request')
NS.TurnInResolver.Resolve = realResolve
print('PASS resolver errors/missing module/malformed decisions fail manual; duplicate guard retained')

-- Consumption checkpoint: choose in the real picker, then hand in using a
-- different ordering from the quest-log snapshot. Verify per-quest cleanup.
resetTurnIn(2)
offerItems = {10399, 5191}
GetQuestID = function() return 101 end
NS.TurnInResolver.Resolve = realResolve
NS.db.settings.rewardMode = 'manual'
NS.db.settings.manualQuality = 3
NS.PrePick.Open(101, true)
local selectedItemID = NS.PrePick.Get(101)
assert(selectedItemID == 5191 and #rewardCalls == 0)
NS.PrePick.Hide()
emit('QUEST_COMPLETE'); drain()
assert(#rewardCalls == 1 and rewardCalls[1] == 2, 'hand-in did not resolve item ID after reorder')
assert(NS.PrePick.Get(101) == 5191, 'pick cleared before successful hand-in event')
emit('QUEST_TURNED_IN', 101, 40, 0)
assert(NS.PrePick.Get(101) == nil and NS.PrePick.Get(202) == 19024)
emit('QUEST_REMOVED', 202)
assert(NS.PrePick.Get(202) == nil)
print('PASS picker -> reordered hand-in -> success cleanup, independent quest and abandon cleanup')

resetTurnIn(2); NS.PrePick.Set(363, 19024)
emit('QUEST_COMPLETE'); drain()
assert(#rewardCalls == 1 and rewardCalls[1] == 1, 'unavailable pick did not use original policy')
resetTurnIn(2); NS.PrePick.Set(363, 19024); NS.db.settings.rewardMode = 'manual'
emit('QUEST_COMPLETE'); drain(); assert(#rewardCalls == 0)
resetTurnIn(2); offerItems = {5191, 5191}; NS.PrePick.Set(363, 5191); NS.db.settings.rewardMode = 'manual'
emit('QUEST_COMPLETE'); drain(); assert(#rewardCalls == 0, 'duplicate item ID guessed a choice')
resetTurnIn(2); NS.PrePick.Set(363, 10399); NS.db.settings.prePickUI = false
emit('QUEST_COMPLETE'); drain(); assert(#rewardCalls == 1 and rewardCalls[1] == 2)
NS.db.settings.prePickUI = true
print('PASS unavailable/ambiguous fallback and display-toggle independence')

resetTurnIn(2); cacheReady = false; NS.PrePick.Set(363, 5191)
emit('QUEST_COMPLETE'); runInitialDeferredAction()
NS.PrePick.Set(363, 10399); cacheReady = true; drain()
assert(#rewardCalls == 1 and rewardCalls[1] == 2, 'retry used stale selection')
resetTurnIn(2); cacheReady = false; NS.PrePick.Set(363, 5191); NS.db.settings.rewardMode = 'manual'
emit('QUEST_COMPLETE'); runInitialDeferredAction()
NS.PrePick.Clear(363); cacheReady = true; drain()
assert(#rewardCalls == 0, 'cleared pick still executed on retry')
resetTurnIn(2); cacheReady = false; NS.PrePick.Set(363, 10399)
emit('QUEST_COMPLETE'); drain()
assert(#rewardCalls == 0 and NS.PrePick.Get(363) == 10399, 'timeout guessed or discarded selection')
for _, cancel in ipairs({
	function() GetQuestID = function() return 999 end end,
	function() emit('QUEST_FINISHED') end,
	function() NS.Auto.state.sessionPaused = true end,
}) do
	resetTurnIn(2); cacheReady = false; NS.PrePick.Set(363, 10399)
	emit('QUEST_COMPLETE'); runInitialDeferredAction(); cancel(); cacheReady = true; drain()
	assert(#rewardCalls == 0 and NS.PrePick.Get(363) == 10399)
end
print('PASS changed/cleared selections on retry, load timeout and identity/pause/close guards with a pick')