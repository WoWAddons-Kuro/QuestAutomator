-- QuestAutomator: shows the reward the addon would take before it is taken.
-- Whenever Blizzard lays out a quest's rewards (QuestInfo_ShowRewards: the quest log's
-- details panel, the NPC's quest detail panel and its reward panel) the scorer the
-- automation uses runs on the choices, and the winning icon gets the action bar's proc
-- glow (ActionButtonSpellAlertTemplate, the retail "spell ready" animation) or, when
-- that template is missing, a pulsing golden border. No setting: the glow appears
-- exactly when the reward would be picked automatically and disappears when it would
-- not (automation off or paused, hand-in off, ignored or repeatable quest, a weapon or
-- a rare reward offered, nothing usable, a single choice).
--
-- Nothing is written into Blizzard's tables: the glow frames are our own, parented to
-- the reward buttons and kept in a table keyed by button; the buttons' type, objectType
-- and ID are only read.
local ADDON, NS = ...
local Rules, Rewards = NS.Rules, NS.Rewards
local Glow = {}
NS.Glow = Glow

Glow.TEMPLATE = "ActionButtonSpellAlertTemplate"
Glow.BORDER = "Interface\\Buttons\\UI-ActionButton-Border"
Glow.RETRY_DELAY = 0.5
Glow.MAX_TRIES = 6

local glows = {} -- reward button -> glow frame
local state = { generation = 0, pending = nil, shown = nil, decision = nil, hooked = false }
Glow.glows = glows
Glow.state = state

--------------------------------------------------------------------------------
-- The glow frame.
--------------------------------------------------------------------------------
local function IconOf(button)
	if type(button.Icon) == "table" then return button.Icon end
	return button
end

local function SizeOf(region)
	local ok, w, h = pcall(region.GetSize, region)
	w, h = tonumber(ok and w) or 0, tonumber(ok and h) or 0
	if w <= 0 then w = 36 end
	if h <= 0 then h = 36 end
	return w, h
end

local function BuildGlow(button)
	local icon = IconOf(button)
	local w, h = SizeOf(icon)
	local ok, frame = pcall(CreateFrame, "Frame", nil, button, Glow.TEMPLATE)
	if ok and type(frame) == "table" and type(frame.ProcLoop) == "table" and frame.ProcLoop.Play then
		NS.features[Glow.TEMPLATE] = true
		frame:SetSize(w * 1.4, h * 1.4)
		frame:SetPoint("CENTER", icon, "CENTER", 0, 0)
		frame.kind = "template"
	else
		NS.features[Glow.TEMPLATE] = false
		frame = CreateFrame("Frame", nil, button)
		frame:SetSize(w * 1.7, h * 1.7)
		frame:SetPoint("CENTER", icon, "CENTER", 0, 0)
		local texture = frame:CreateTexture(nil, "OVERLAY")
		texture:SetTexture(Glow.BORDER)
		texture:SetBlendMode("ADD")
		texture:SetAllPoints(frame)
		texture:SetVertexColor(1, 0.85, 0.3)
		frame.texture = texture
		local group = frame:CreateAnimationGroup()
		local alpha = group:CreateAnimation("Alpha")
		alpha:SetFromAlpha(1)
		alpha:SetToAlpha(0.3)
		alpha:SetDuration(0.6)
		group:SetLooping("BOUNCE")
		frame.pulse = group
		frame.kind = "border"
	end
	local okLevel, level = pcall(button.GetFrameLevel, button)
	if okLevel and type(level) == "number" then pcall(frame.SetFrameLevel, frame, level + 5) end
	frame:Hide()
	return frame
end

local function ShowGlow(button)
	local frame = glows[button]
	if not frame then
		frame = BuildGlow(button)
		glows[button] = frame
	end
	frame:Show()
	if frame.ProcLoop then
		frame.ProcLoop:Play()
	elseif frame.pulse then
		frame.pulse:Play()
	end
	state.shown = button
end

function Glow.HideAll()
	for _, frame in pairs(glows) do
		if frame.ProcLoop then frame.ProcLoop:Stop() end
		if frame.pulse then frame.pulse:Stop() end
		frame:Hide()
	end
	state.shown = nil
	state.decision = nil
end

-- The reward button carrying the glow, if any.
function Glow.Shown()
	return state.shown
end

--------------------------------------------------------------------------------
-- What reward panel is on screen (client adapter), and what the automation would do.
--------------------------------------------------------------------------------
local function Context()
	-- { questID, questLog, buttons (choice item buttons with :GetID()), frame, source }
	-- from the client adapter; nil when no reward panel is on screen.
	local ctx = NS.Client.RewardContext()
	if not ctx then return nil end
	ctx.rewardsFrame = ctx.frame
	return ctx
end

local function FrameShown(frame)
	local ok, shown = pcall(frame.IsShown, frame)
	return ok and shown == true
end

-- Would the automation pick a reward here? The decision (with index) when it would,
-- { pending = true } plus the choices while item data is missing, nil otherwise.
function Glow.Decide(ctx)
	if not NS.db then return nil end
	local s = NS.db.settings
	if not (s.enabled and s.turnIn) then return nil, "off" end
	if NS.Auto and NS.Auto.SessionPaused() then return nil, "paused" end
	local questID = ctx.questID
	local repeatable = questID and NS.Client.IsQuestRepeatable(questID) or false
	local ok, why = NS.Auto.MayTurnIn(questID, repeatable)
	if not ok then return nil, why end
	local n = NS.SafeNumber(ctx.source.Count()) or 0
	if n < 2 then return nil, "nochoice" end
	local choices = Rewards.Gather(n, ctx.source)
	local decision = Rewards.Evaluate(choices, s, Rules.Player())
	if decision.pending then return decision, "pending", choices, decision end
	if not decision.index then return nil, decision.reason, choices, decision end
	return decision, "pick", choices, decision
end

local function FindButton(ctx, index)
	for _, button in ipairs(ctx.buttons or {}) do
		local ok, id = pcall(button.GetID, button)
		if ok and id == index then return button end
	end
	return nil
end

-- Re-evaluates the rewards on show; returns the glowing button, if any.
function Glow.Refresh(attempt)
	attempt = attempt or 1
	state.generation = state.generation + 1
	local generation = state.generation
	state.pending = nil
	Glow.HideAll()
	local ctx = Context()
	if not ctx then return nil end
	local decision, why, choices = Glow.Decide(ctx)
	state.lastReason = why
	if not decision then return nil end
	if decision.pending then
		if attempt >= Glow.MAX_TRIES then return nil end
		for _, c in ipairs(choices or {}) do
			if c.loaded == false and c.itemID then NS.Call("C_Item.RequestLoadItemDataByID", c.itemID) end
		end
		state.pending = { generation = generation, attempt = attempt, questID = ctx.questID }
		NS.After(Glow.RETRY_DELAY, function() Glow.Retry(generation) end)
		return nil
	end
	local button = FindButton(ctx, decision.index)
	if not button then return nil end
	ShowGlow(button)
	state.decision = decision
	return button
end

function Glow.Retry(generation)
	local p = state.pending
	if not p or p.generation ~= generation then return end
	state.pending = nil
	local ctx = Context()
	if not ctx or ctx.questID ~= p.questID or not FrameShown(ctx.rewardsFrame) then return end
	Glow.Refresh(p.attempt + 1)
end

-- Settings changed (slash command, settings page, menu): the pick may differ now.
function Glow.OnSettingsChanged()
	local ctx = Context()
	if ctx and FrameShown(ctx.rewardsFrame) then
		Glow.Refresh(1)
	else
		Glow.HideAll()
	end
end

--------------------------------------------------------------------------------
-- Hook (names from the client adapter: QuestInfo_Display, QuestInfo_ShowRewards, and on
-- Era QuestFrameItems_Update for the quest log). QuestInfo.lua lays a panel out with QuestInfo_Display(template, ...),
-- which walks template.elements and calls each entry; the templates
-- (QUEST_TEMPLATE_DETAIL, _LOG, _REWARD, _MAP_REWARDS) hold QuestInfo_ShowRewards as a
-- function *value*, so a hook on that global name never runs for a template-driven
-- layout (found in-game: no glow in the quest log). QuestInfo_Display itself is called
-- by name from QuestMapFrame_ShowQuestDetails and the QuestFrame panels, so it is the
-- hook; QuestInfo_ShowRewards is hooked as well for the direct calls QuestFrame makes on
-- QUEST_ITEM_UPDATE and LEARNED_SPELL_IN_SKILL_LINE.
--------------------------------------------------------------------------------
local function OnLayout()
	local ok, err = pcall(Glow.Refresh, 1)
	if not ok then NS.WarnOnce("glow", err) end
end

function Glow.Install()
	if state.hooked then return true end
	if type(hooksecurefunc) ~= "function" then
		NS.features["hooksecurefunc"] = false
		return false
	end
	local any = false
	for _, name in ipairs(NS.Client.RewardLayoutHooks()) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, OnLayout)
			NS.features[name] = true
			any = true
		else
			NS.features[name] = false
		end
	end
	state.hooked = any
	return any
end

--------------------------------------------------------------------------------
-- `/qam why`: the rewards on screen, how each scored, and what would happen.
--------------------------------------------------------------------------------
local L = NS.L

function Glow.WhyText(why, decision)
	if why == "off" then return L["the automation is off"] end
	if why == "paused" then return L["paused for this session"] end
	if why == "ignored" then return L["the quest is on the ignore list"] end
	if why == "repeatable" then return L["repeatable quests are not handed in automatically"] end
	if why == "nochoice" then return L["there is nothing to choose"] end
	if why == "pending" then return L["the item data did not load in time"] end
	return Rewards.ReasonText(why, decision)
end

local function ChoiceLine(c)
	local bits = {}
	if c.lootType ~= Rewards.LOOT_ITEM then
		bits[#bits + 1] = L["currency"]
	else
		bits[#bits + 1] = NS.QualityName(c.quality or 0)
		if c.classID == Rules.CLASS_ARMOR then
			bits[#bits + 1] = Rules.ArmorName(c.subclassID)
		elseif Rules.IsWeapon(c.classID, c.subclassID) then
			bits[#bits + 1] = Rules.WeaponName(c.subclassID)
		end
		local stats = {}
		for key, amount in pairs(c.stats or {}) do
			stats[#stats + 1] = Rewards.FormatAmount(amount) .. " " .. Rules.StatName(key)
		end
		table.sort(stats)
		if #stats > 0 then bits[#bits + 1] = table.concat(stats, ", ") end
		if c.loaded == false then
			bits[#bits + 1] = L["item data not loaded"]
		else
			bits[#bits + 1] = NS.FormatMoney((c.sellPrice or 0) * (c.count or 1))
		end
		if c.fit then
			if c.fit.score > 0 then
				bits[#bits + 1] = string.format(L["score %.1f"], c.fit.score)
			elseif c.fit.why == "notgear" then
				bits[#bits + 1] = L["not equipment"]
			else
				bits[#bits + 1] = L["cannot use"]
			end
			if c.fit.otherKind then bits[#bits + 1] = L["not the preferred weapon kind"] end
		end
	end
	NS.Print("  %d. %s: %s", c.index, Rewards.ChoiceLabel(c), table.concat(bits, " | "))
end

function Glow.Explain()
	local ctx = Context()
	if not ctx or not FrameShown(ctx.rewardsFrame) then
		NS.Print(L["No quest rewards are on screen. Open a quest in the log or talk to a quest giver, then try again."])
		return false
	end
	local title = ctx.questID and NS.Client.QuestTitle(ctx.questID) or nil
	if not title or title == "" then title = NS.SafeString(NS.Call("GetTitleText")) end
	if not title or title == "" then title = ctx.questID and ("#" .. ctx.questID) or "?" end
	NS.Print(L["Rewards of %s (%s):"], title, ctx.questLog and L["quest log"] or L["quest giver"])
	local decision, why, choices, evaluated = Glow.Decide(ctx)
	for _, c in ipairs(choices or {}) do ChoiceLine(c) end
	if decision and decision.index then
		NS.Print(L["Would take #%d: %s"], decision.index, Rewards.Describe(decision))
	else
		NS.Print(L["Left to you: %s"], Glow.WhyText(why, evaluated))
	end
	return true
end

function Glow.DebugReport()
	local shown = state.shown
	local okName, name = pcall(function() return shown and shown:GetName() end)
	NS.Print("Glow: hooked %s, last reason %s, glowing %s, frames %d, pending %s",
		tostring(state.hooked), tostring(state.lastReason), tostring(okName and name or (shown and "button") or "none"),
		#NS.SortedKeys(glows), state.pending and ("attempt " .. state.pending.attempt) or "none")
end

Glow.Install()
NS.RegisterEvent("PLAYER_LOGIN", function() Glow.Install() end)
