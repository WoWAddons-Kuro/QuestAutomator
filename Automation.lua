-- Quest Automator: the event flow. Gossip and greeting lists are walked
-- for quests to hand in (first) and quests to take (second); QUEST_DETAIL is
-- accepted, QUEST_PROGRESS completed, QUEST_COMPLETE handed in with the reward
-- picked by Rewards.lua. Holding the pause key (Shift by default) while
-- talking to an NPC keeps the whole interaction manual.
--
-- Everything here calls the same functions Blizzard's own QuestFrame.lua and
-- GossipFrameShared.lua call on a button click (build 69893 export):
-- C_GossipInfo.SelectAvailableQuest / SelectActiveQuest (by quest ID),
-- SelectAvailableQuest / SelectActiveQuest (by greeting index), AcceptQuest,
-- AcknowledgeAutoAcceptQuest, CompleteQuest, GetQuestReward, ConfirmAcceptQuest.
--
-- Never from inside the event: GOSSIP_SHOW, GOSSIP_CLOSED, QUEST_GREETING,
-- QUEST_DETAIL, QUEST_PROGRESS, QUEST_COMPLETE, QUEST_FINISHED and
-- QUEST_ACCEPT_CONFIRM are all SynchronousEvent (GossipInfoDocumentation.lua,
-- QuestLogDocumentation.lua, QuestOfferDocumentation.lua), so a selection made
-- in our GOSSIP_SHOW handler can close the gossip before Blizzard's
-- CustomGossipManager has handled the same GOSSIP_SHOW. GossipFrame then opens
-- on a conversation that is already over, and when QUEST_DETAIL replaces it
-- with QuestFrame its OnHide calls C_GossipInfo.CloseGossip() (no
-- interactionIsContinuing was recorded), ending the NPC interaction under the
-- quest panel: the quest is not taken and the NPC does not answer again until
-- the player walks away. So every action waits one frame (Defer), when every
-- handler of the event has run, exactly as a click on Blizzard's button would.
local ADDON, NS = ...
local L = NS.L
local Rules, Rewards, Client = NS.Rules, NS.Rewards, NS.Client
local format = string.format
local Auto = {}
NS.Auto = Auto

Auto.PAUSE_WINDOW = 60    -- seconds an interaction stays manual after the key was held
Auto.MAX_LOAD_TRIES = 6   -- retries while waiting for item data (RETRY_DELAY apart)
Auto.RETRY_DELAY = 0.5
Auto.MAX_ATTEMPTS = 1     -- selections of the same quest per interaction (guards against loops)
Auto.REPEAT_WINDOW = 2    -- seconds within which the same accept / complete / reward is not sent again
Auto.ANSWER_TIMEOUT = 3   -- seconds a selection may go unanswered before the conversation is closed

local state = {
	sessionPaused = false,
	pausedNPC = nil,  -- GUID of the NPC the pause key was held for ("-" when there was none)
	pausedAt = 0,
	offered = {},     -- questID -> { title, trivial, repeatable, turnIn } for quests this addon selected
	attempts = {},    -- "accept:123" -> selections this interaction
	sent = {},        -- "accept:123" -> time the request went out (duplicate events are dropped)
	stage = nil,      -- "gossip" | "greeting" | "detail" | "progress" | "complete"
	pending = nil,    -- { questID, attempt } while item data is loading
	waiting = nil,    -- { questID, title } after a selection, until the NPC answers
	token = 0,        -- bumped by every stage event; a deferred action runs only if still current
	byUs = {},        -- accept = questID, turnIn = questID
	lastNPC = nil,
}
Auto.state = state

--------------------------------------------------------------------------------
-- Player input and the NPC in front of the player.
--------------------------------------------------------------------------------
local MODIFIER_FN = { SHIFT = "IsShiftKeyDown", CTRL = "IsControlKeyDown", ALT = "IsAltKeyDown" }

function Auto.ModifierDown()
	local fn = MODIFIER_FN[NS.db and NS.db.settings.modifier or "SHIFT"]
	if not fn then return false end
	return NS.SafeBool(NS.Call(fn))
end

function Auto.NPCGUID()
	return NS.SafeString(NS.Call("UnitGUID", "npc")) or NS.SafeString(NS.Call("UnitGUID", "questnpc"))
end

function Auto.NPCName()
	return NS.SafeString(NS.Call("UnitName", "npc")) or NS.SafeString(NS.Call("UnitName", "questnpc"))
end

-- Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn> -> npcID
function Auto.NPCID(guid)
	if type(guid) ~= "string" then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then return tonumber(id) end
	return nil
end

function Auto.SessionPaused()
	return state.sessionPaused
end

function Auto.SetSessionPaused(paused)
	state.sessionPaused = paused and true or false
	NS.Print(state.sessionPaused and L["Paused for this session. /qam resume or /qam pause off switches it back on."]
		or L["Automation resumed."])
	NS.OnSettingsChanged()
end

-- nil when the automation may act, else why not.
function Auto.Blocked()
	if not NS.db then return "notloaded" end
	local s = NS.db.settings
	if not s.enabled then return "disabled" end
	if state.sessionPaused then return "session" end
	local guid = Auto.NPCGUID()
	if guid and guid ~= state.lastNPC then
		-- A different NPC: the previous interaction is over.
		state.lastNPC = guid
		state.attempts = {}
		if state.pausedNPC and state.pausedNPC ~= "-" and state.pausedNPC ~= guid then state.pausedNPC = nil end
	end
	if Auto.ModifierDown() then
		state.pausedNPC = guid or "-"
		state.pausedAt = NS.Now()
		return "modifier"
	end
	if state.pausedNPC then
		local sameInteraction = (guid == nil) or (state.pausedNPC == "-") or (state.pausedNPC == guid)
		if sameInteraction and NS.Now() - state.pausedAt < Auto.PAUSE_WINDOW then
			return "interaction"
		end
		state.pausedNPC = nil
	end
	local npcID = Auto.NPCID(guid)
	if npcID and NS.db.ignoredNPCs[npcID] then return "npc" end
	return nil
end

function Auto.EndInteraction()
	state.pausedNPC = nil
	state.attempts = {}
	state.offered = {}
	state.pending = nil
	state.waiting = nil
end

local function TryOnce(kind, questID)
	local key = kind .. ":" .. tostring(questID)
	local n = (state.attempts[key] or 0) + 1
	state.attempts[key] = n
	return n <= Auto.MAX_ATTEMPTS
end

-- The client sometimes delivers QUEST_DETAIL / QUEST_PROGRESS / QUEST_COMPLETE
-- twice for one panel (seen in the log: "detail: accept 445" twice in the same
-- second). A request that already went out is not sent again for a moment.
local function SendOnce(kind, questID)
	local key = kind .. ":" .. tostring(questID)
	local now = NS.Now()
	local last = state.sent[key]
	if last and now - last < Auto.REPEAT_WINDOW then
		NS.Log("skip", "%s: already sent for %s", kind, tostring(questID))
		return false
	end
	state.sent[key] = now
	return true
end

-- Run fn on the next frame, after every handler of the current (synchronous)
-- event has run, Blizzard's frames included. A later stage event replaces an
-- action that has not run yet, so an event delivered twice acts once; a stage
-- that has ended in between (QUEST_FINISHED, GOSSIP_CLOSED) cancels it.
local function Defer(stage, fn)
	state.token = state.token + 1
	local token = state.token
	NS.After(0, function()
		if token ~= state.token or state.stage ~= stage then return end
		fn()
	end)
end
Auto.Defer = Defer

--------------------------------------------------------------------------------
-- A selection the NPC never answers. After a gossip or greeting selection the
-- quest panel should follow; if no panel came and none of Blizzard's frames is
-- open, the conversation is closed so the NPC can be talked to again (what
-- GossipFrame's and QuestFrame's OnHide would have done).
--------------------------------------------------------------------------------
local function FrameShown(name)
	local frame = _G[name]
	if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false end
	local ok, shown = pcall(frame.IsShown, frame)
	return ok and NS.SafeBool(shown)
end

-- True when the client still holds a gossip or quest giver interaction; true as
-- well when it cannot tell (closing an interaction that is not open is harmless).
function Auto.Interacting()
	local types = Enum and Enum.PlayerInteractionType
	if not (types and types.Gossip and types.QuestGiver) then return true end
	local gossip = NS.Call("C_PlayerInteractionManager.IsInteractingWithNpcOfType", types.Gossip)
	local quest = NS.Call("C_PlayerInteractionManager.IsInteractingWithNpcOfType", types.QuestGiver)
	if gossip == nil and quest == nil then return true end
	return NS.SafeBool(gossip) or NS.SafeBool(quest)
end

local function AwaitAnswer(questID, title)
	local w = { questID = questID, title = title }
	state.waiting = w
	NS.After(Auto.ANSWER_TIMEOUT, function() Auto.CheckAnswer(w) end)
end

function Auto.Answered()
	state.waiting = nil
end

function Auto.CheckAnswer(w)
	if state.waiting ~= w then return end
	state.waiting = nil
	if FrameShown("GossipFrame") or FrameShown("QuestFrame") then return end
	if not Auto.Interacting() then return end
	NS.Log("act", "no answer to %s (%s): closing the conversation", tostring(w.title), tostring(w.questID))
	NS.Call("C_GossipInfo.CloseGossip")
	NS.Call("CloseQuest")
	state.stage = nil
	Auto.EndInteraction()
	NS.Announce(L["%s did not open; the conversation was closed so you can talk to the NPC again."],
		tostring(w.title or (w.questID and ("#" .. w.questID)) or "?"))
end

--------------------------------------------------------------------------------
-- Repeatable: the offer's flag, or a recurring frequency. The numeric frequency
-- encodings (Enum.QuestFrequency vs LE_QUEST_FREQUENCY_*) are decoded in Client/;
-- here `offer.frequency` is a Client.FREQUENCY_* string.
--------------------------------------------------------------------------------
local function IsRepeatable(offer)
	return offer.isRepeatable or Client.IsRecurringFrequency(offer.frequency)
end

function Auto.MayAccept(questID, trivial, repeatable)
	local s = NS.db.settings
	if questID and NS.db.ignoredQuests[questID] then return false, "ignored" end
	if trivial and not s.acceptTrivial then return false, "trivial" end
	if repeatable and not s.acceptRepeatable then return false, "repeatable" end
	return true
end

function Auto.MayTurnIn(questID, repeatable)
	local s = NS.db.settings
	if questID and NS.db.ignoredQuests[questID] then return false, "ignored" end
	if repeatable and not s.turnInRepeatable then return false, "repeatable" end
	return true
end

local function QuestTitle(questID, fallback)
	local offered = questID and state.offered[questID]
	if offered and offered.title then return offered.title end
	local title = questID and Client.QuestTitle(questID)
	if title and title ~= "" then return title end
	title = NS.SafeString(NS.Call("GetTitleText"))
	if title and title ~= "" then return title end
	return fallback or (questID and ("#" .. questID)) or "?"
end

--------------------------------------------------------------------------------
-- Gossip (C_GossipInfo) and the plain greeting panel.
--------------------------------------------------------------------------------
-- A quest the player already has is never picked up again (a list the server
-- sends right after an accept may still carry it).
local function OnQuest(questID)
	return questID and NS.SafeBool(NS.Call("C_QuestLog.IsOnQuest", questID)) or false
end

function Auto.OnGossipShow()
	if not NS.loaded then return end
	state.stage = "gossip"
	Auto.Answered()
	Defer("gossip", Auto.ActGossip)
end

function Auto.ActGossip()
	local why = Auto.Blocked()
	if why then
		NS.Log("skip", "gossip: %s", why)
		return
	end
	local s = NS.db.settings
	if s.turnIn then
		local active = NS.Call("C_GossipInfo.GetActiveQuests")
		for _, raw in ipairs(type(active) == "table" and active or {}) do
			local q = Client.GossipQuestInfo(raw)
			local questID = q.questID
			local repeatable = IsRepeatable(q)
			if questID and (q.isComplete or Client.IsQuestComplete(questID)) and Auto.MayTurnIn(questID, repeatable) and TryOnce("turnin", questID) then
				state.offered[questID] = { title = q.title, repeatable = repeatable, trivial = q.isTrivial, turnIn = true }
				NS.Log("act", "gossip: hand in %s (%d)", tostring(q.title), questID)
				AwaitAnswer(questID, q.title)
				NS.Call("C_GossipInfo.SelectActiveQuest", questID)
				return
			end
		end
	end
	if s.accept then
		local available = NS.Call("C_GossipInfo.GetAvailableQuests")
		for _, raw in ipairs(type(available) == "table" and available or {}) do
			local q = Client.GossipQuestInfo(raw)
			local questID = q.questID
			local repeatable = IsRepeatable(q)
			local ok, reason = true, nil
			if not questID then ok, reason = false, "no questID"
			elseif OnQuest(questID) then ok, reason = false, "already on quest"
			else ok, reason = Auto.MayAccept(questID, q.isTrivial, repeatable) end
			if ok and not TryOnce("accept", questID) then ok, reason = false, "already tried" end
			if ok then
				state.offered[questID] = { title = q.title, repeatable = repeatable, trivial = q.isTrivial }
				NS.Log("act", "gossip: take %s (%d)", tostring(q.title), questID)
				AwaitAnswer(questID, q.title)
				NS.Call("C_GossipInfo.SelectAvailableQuest", questID)
				return
			end
			NS.Log("skip", "gossip: available %s (%s): %s [trivial=%s rep=%s freq=%s]", tostring(q.title), tostring(questID),
				tostring(reason), tostring(q.isTrivial), tostring(q.isRepeatable), q.frequency)
		end
	end
end

function Auto.OnGossipClosed(interactionIsContinuing)
	-- The gossip is gone either way: a gossip action not yet run must not run.
	if state.stage == "gossip" then state.stage = nil end
	if NS.SafeBool(interactionIsContinuing) then return end
	Auto.EndInteraction()
end

function Auto.OnQuestGreeting()
	if not NS.loaded then return end
	state.stage = "greeting"
	Auto.Answered()
	Defer("greeting", Auto.ActGreeting)
end

function Auto.ActGreeting()
	local why = Auto.Blocked()
	if why then
		NS.Log("skip", "greeting: %s", why)
		return
	end
	local s = NS.db.settings
	if s.turnIn then
		local numActive = NS.SafeNumber(NS.Call("GetNumActiveQuests")) or 0
		for i = 1, numActive do
			local title, isComplete = NS.Call("GetActiveTitle", i)
			local questID = Client.ActiveQuestID(i)  -- nil on Era
			local repeatable = Client.IsQuestRepeatable(questID)
			title = NS.SafeString(title)
			if NS.SafeBool(isComplete) and Auto.MayTurnIn(questID, repeatable) and TryOnce("turnin", questID or title or i) then
				if questID then
					state.offered[questID] = { title = title, repeatable = repeatable, trivial = NS.SafeBool(NS.Call("IsActiveQuestTrivial", i)), turnIn = true }
				end
				NS.Log("act", "greeting: hand in %s (%s)", tostring(title), tostring(questID))
				AwaitAnswer(questID, title)
				NS.Call("SelectActiveQuest", i)
				return
			end
		end
	end
	if s.accept then
		local numAvailable = NS.SafeNumber(NS.Call("GetNumAvailableQuests")) or 0
		NS.Log("info", "greeting: %d active, %d available (turnIn %s, accept %s)",
			NS.SafeNumber(NS.Call("GetNumActiveQuests")) or 0, numAvailable, tostring(s.turnIn), tostring(s.accept))
		for i = 1, numAvailable do
			local q = Client.AvailableQuestInfo(i)  -- questID is nil on Era
			local questID = q.questID
			local repeatable = IsRepeatable(q)
			local title = NS.SafeString(NS.Call("GetAvailableTitle", i))
			local ok, reason = true, nil
			if OnQuest(questID) then ok, reason = false, "already on quest"
			else ok, reason = Auto.MayAccept(questID, q.isTrivial, repeatable) end
			if ok and not TryOnce("accept", questID or title or i) then ok, reason = false, "already tried" end
			if ok then
				if questID then
					state.offered[questID] = { title = title, repeatable = repeatable, trivial = q.isTrivial }
				end
				NS.Log("act", "greeting: take %s (%s)", tostring(title), tostring(questID))
				AwaitAnswer(questID, title)
				NS.Call("SelectAvailableQuest", i)
				return
			end
			NS.Log("skip", "greeting: available %d %s (%s): %s [trivial=%s rep=%s freq=%s raw=%s]", i, tostring(title), tostring(questID),
				tostring(reason), tostring(q.isTrivial), tostring(q.isRepeatable), q.frequency, tostring(q.rawFrequency))
		end
	end
end

--------------------------------------------------------------------------------
-- Quest detail (accept), progress (complete), reward (hand in).
--------------------------------------------------------------------------------
function Auto.OnQuestDetail(questStartItemID)
	if not NS.loaded then return end
	state.stage = "detail"
	Auto.Answered()
	Defer("detail", function() Auto.ActDetail(questStartItemID) end)
end

function Auto.ActDetail(questStartItemID)
	if not NS.db.settings.accept then return end
	local startItem = NS.SafeNumber(questStartItemID)
	if startItem and startItem ~= 0 then return end -- Blizzard turns item-started quests into a pop-up itself
	local why = Auto.Blocked()
	if why then
		NS.Log("skip", "detail: %s", why)
		return
	end
	local questID = NS.SafeNumber(NS.Call("GetQuestID"))
	if questID == 0 then questID = nil end
	local offered = questID and state.offered[questID]
	if not offered then
		-- The player (or the server) opened this quest; apply the same rules as far as the client answers.
		local trivial = Client.IsQuestTrivial(questID)
		local repeatable = Client.IsQuestRepeatable(questID)
		local ok, reason = Auto.MayAccept(questID, trivial, repeatable)
		if not ok then
			NS.Log("skip", "detail: %s (%s)", reason, tostring(questID))
			return
		end
	end
	if NS.SafeBool(NS.Call("QuestFlagsPVP")) then
		NS.Log("skip", "detail: pvp quest %s", tostring(questID))
		NS.Announce(L["%s flags you for PvP; accept it yourself."], QuestTitle(questID))
		return
	end
	if OnQuest(questID) then
		NS.Log("skip", "detail: already in the quest log (%s)", tostring(questID))
		return
	end
	if not SendOnce("accept", questID) then return end
	state.byUs.accept = questID or true
	if NS.SafeBool(NS.Call("QuestGetAutoAccept")) then
		NS.Log("act", "detail: acknowledge %s", tostring(questID))
		NS.Call("AcknowledgeAutoAcceptQuest")
	else
		NS.Log("act", "detail: accept %s", tostring(questID))
		NS.Call("AcceptQuest")
	end
end

local function TurnInAllowed(stage)
	if not NS.db.settings.turnIn then return nil end
	local why = Auto.Blocked()
	if why then
		NS.Log("skip", "%s: %s", stage, why)
		return nil
	end
	local questID = NS.SafeNumber(NS.Call("GetQuestID"))
	if questID == 0 then questID = nil end
	local offered = questID and state.offered[questID]
	local repeatable
	if offered then
		repeatable = offered.repeatable
	else
		repeatable = Client.IsQuestRepeatable(questID)
	end
	local ok, reason = Auto.MayTurnIn(questID, repeatable)
	if not ok then
		NS.Log("skip", "%s: %s (%s)", stage, reason, tostring(questID))
		return nil
	end
	local money = NS.SafeNumber(NS.Call("GetQuestMoneyToGet")) or 0
	if money > 0 then
		NS.Log("skip", "%s: needs %d copper", stage, money)
		NS.Announce(L["%s costs %s to hand in; do it yourself."], QuestTitle(questID), NS.FormatMoney(money))
		return nil
	end
	return questID or true
end

function Auto.OnQuestProgress()
	if not NS.loaded then return end
	state.stage = "progress"
	Auto.Answered()
	Defer("progress", Auto.ActProgress)
end

function Auto.ActProgress()
	local questID = TurnInAllowed("progress")
	if not questID then return end
	if not NS.SafeBool(NS.Call("IsQuestCompletable")) then
		NS.Log("skip", "progress: not completable (%s)", tostring(questID))
		return
	end
	if not SendOnce("complete", questID) then return end
	NS.Log("act", "progress: complete %s", tostring(questID))
	NS.Call("CompleteQuest")
end

function Auto.OnQuestComplete()
	if not NS.loaded then return end
	state.stage = "complete"
	state.pending = nil
	Auto.Answered()
	Defer("complete", Auto.ActComplete)
end

function Auto.ActComplete()
	local questID = TurnInAllowed("complete")
	if not questID then return end
	Auto.Choose(questID, 1)
end

function Auto.TakeReward(questID, index, decision)
	state.pending = nil
	if not SendOnce("reward", questID) then return end
	state.byUs.turnIn = questID
	state.pending = nil
	if decision and decision.choice then
		NS.chardb.counts.chosen = NS.chardb.counts.chosen + 1
		NS.Announce(L["Reward: %s (%s)"], Rewards.ChoiceLabel(decision.choice), Rewards.Describe(decision))
	end
	NS.Log("act", "complete: reward %d for %s", index, tostring(questID))
	NS.Call("GetQuestReward", index)
end

function Auto.LeaveChoice(reason, decision)
	state.pending = nil
	NS.chardb.counts.left = NS.chardb.counts.left + 1
	NS.Log("skip", "complete: left to the player (%s)", reason)
	NS.Announce(L["Choose the reward yourself: %s."], Rewards.ReasonText(reason, decision))
end

function Auto.Choose(questID, attempt)
	local rewardChoiceCount = NS.SafeNumber(NS.Call("GetNumQuestChoices")) or 0
	local rewardChoices = rewardChoiceCount > 1 and Rewards.Gather(rewardChoiceCount) or {}
	local turnInContext = {
		questID = NS.SafeNumber(questID),
		rewardChoiceCount = rewardChoiceCount,
		rewardChoices = rewardChoices,
		settings = NS.db.settings,
		player = rewardChoiceCount > 1 and Rules.Player() or nil,
	}
	local ok, decision = pcall(function()
		local resolver = NS.TurnInResolver
		local result = resolver.Resolve(turnInContext)
		if not resolver.IsDecisionValid(turnInContext, result) then error("invalid turn-in resolver result") end
		return result
	end)
	if not ok then
		NS.WarnOnce("turn-in-resolver", tostring(decision))
		Auto.LeaveChoice(L["the reward resolver failed; choose manually"])
		return
	end
	if decision.action == "wait" then
		if attempt >= Auto.MAX_LOAD_TRIES then
			Auto.LeaveChoice("pending")
			return
		end
		for _, c in ipairs(rewardChoices) do
			if c.loaded == false and c.itemID then NS.Call("C_Item.RequestLoadItemDataByID", c.itemID) end
		end
		state.pending = { questID = questID, attempt = attempt }
		NS.After(Auto.RETRY_DELAY, function() Auto.Retry(questID, attempt) end)
		return
	end
	if decision.action == "submit" then
		Auto.TakeReward(questID, decision.rewardChoiceIndex, decision.rewardDecision)
	else
		Auto.LeaveChoice(decision.reason, decision.rewardDecision)
	end
end

function Auto.Retry(questID, attempt)
	local p = state.pending
	if not p or p.questID ~= questID or p.attempt ~= attempt then return end
	local current = NS.SafeNumber(NS.Call("GetQuestID"))
	if state.stage ~= "complete" or (questID ~= true and current ~= questID) then
		state.pending = nil
		return
	end
	if Auto.Blocked() then
		state.pending = nil
		return
	end
	state.pending = nil
	Auto.Choose(questID, attempt + 1)
end

function Auto.OnQuestItemUpdate()
	local p = state.pending
	if p then NS.After(0, function() Auto.Retry(p.questID, p.attempt) end) end
end

function Auto.OnQuestFinished()
	state.stage = nil
	state.pending = nil
	-- The panel is gone: whatever opens next is a new request, not a duplicate.
	state.sent = {}
end

--------------------------------------------------------------------------------
-- Results and party confirmations.
--------------------------------------------------------------------------------
function Auto.OnQuestAccepted(questID)
	if not NS.loaded then return end
	questID = NS.SafeNumber(questID)
	local mine = state.byUs.accept
	if mine == nil then return end
	if mine ~= true and questID and mine ~= questID then return end
	state.byUs.accept = nil
	NS.chardb.counts.accepted = NS.chardb.counts.accepted + 1
	NS.Announce(L["Accepted: %s"], QuestTitle(questID))
	if questID then state.offered[questID] = nil end
end

function Auto.OnQuestTurnedIn(questID, xp, money)
	if not NS.loaded then return end
	questID = NS.SafeNumber(questID)
	local mine = state.byUs.turnIn
	if mine == nil then return end
	if mine ~= true and questID and mine ~= questID then return end
	state.byUs.turnIn = nil
	NS.chardb.counts.turnedIn = NS.chardb.counts.turnedIn + 1
	local bits = {}
	xp, money = NS.SafeNumber(xp) or 0, NS.SafeNumber(money) or 0
	if xp > 0 then bits[#bits + 1] = format(L["%d XP"], xp) end
	if money > 0 then bits[#bits + 1] = NS.FormatMoney(money) end
	NS.Announce(L["Handed in: %s%s"], QuestTitle(questID), #bits > 0 and (" (" .. table.concat(bits, ", ") .. ")") or "")
	if questID then state.offered[questID] = nil end
end

function Auto.OnAcceptConfirm(name, questTitle, questID)
	if not NS.loaded then return end
	local s = NS.db.settings
	if not (s.enabled and s.accept and s.confirmPartyQuests) then return end
	if state.sessionPaused or Auto.ModifierDown() then return end
	questID = NS.SafeNumber(questID)
	if questID and NS.db.ignoredQuests[questID] then return end
	state.byUs.accept = questID or true
	if questID then state.offered[questID] = { title = NS.SafeString(questTitle) } end
	NS.Log("act", "party: confirm %s from %s", tostring(questTitle), tostring(name))
	-- Next frame: Blizzard's own handler of this synchronous event shows the
	-- QUEST_ACCEPT popup, which can only be hidden once it is there.
	NS.After(0, function()
		NS.Call("ConfirmAcceptQuest")
		NS.Call("StaticPopup_Hide", "QUEST_ACCEPT")
	end)
end

--------------------------------------------------------------------------------
-- Ignore lists and status.
--------------------------------------------------------------------------------
local function CurrentQuestID()
	local questID = NS.SafeNumber(NS.Call("GetQuestID"))
	if questID and questID > 0 then return questID end
	return nil
end

function Auto.IgnoreCommand(rest)
	local what = tostring(rest or ""):lower():match("^%s*(.-)%s*$")
	if what == "list" then
		Auto.PrintIgnored()
		return
	end
	local questID = CurrentQuestID()
	local guid = Auto.NPCGUID()
	local npcID = Auto.NPCID(guid)
	if what == "" then what = (questID and "quest") or (npcID and "npc") or "" end
	if what == "quest" then
		if not questID then
			NS.Print(L["Open the quest first (talk to the NPC and pick it), then type /qam ignore quest."])
			return
		end
		if NS.db.ignoredQuests[questID] then
			NS.db.ignoredQuests[questID] = nil
			NS.Print(L["Quest %s (%d) is automated again."], QuestTitle(questID), questID)
		else
			NS.db.ignoredQuests[questID] = QuestTitle(questID)
			NS.Print(L["Quest %s (%d) is now left to you."], QuestTitle(questID), questID)
		end
	elseif what == "npc" then
		if not npcID then
			NS.Print(L["Talk to the NPC first, then type /qam ignore npc."])
			return
		end
		if NS.db.ignoredNPCs[npcID] then
			local name = NS.db.ignoredNPCs[npcID]
			NS.db.ignoredNPCs[npcID] = nil
			NS.Print(L["NPC %s (%d) is automated again."], tostring(name or Auto.NPCName() or npcID), npcID)
		else
			NS.db.ignoredNPCs[npcID] = Auto.NPCName() or tostring(npcID)
			NS.Print(L["NPC %s (%d) is now left to you."], NS.db.ignoredNPCs[npcID], npcID)
		end
	else
		NS.Print(L["/qam ignore [npc|quest] - never automate the NPC or quest in front of you"])
		NS.Print(L["/qam ignore list | unignore <id> - review or clear the ignore lists"])
	end
end

function Auto.UnignoreCommand(rest)
	local id = tonumber(tostring(rest or ""):match("%d+"))
	if not id then
		Auto.PrintIgnored()
		return
	end
	local removed = false
	if NS.db.ignoredQuests[id] then
		NS.db.ignoredQuests[id] = nil
		removed = true
	end
	if NS.db.ignoredNPCs[id] then
		NS.db.ignoredNPCs[id] = nil
		removed = true
	end
	NS.Print(removed and L["%d removed from the ignore lists."] or L["%d is not on any ignore list."], id)
end

function Auto.PrintIgnored()
	local any = false
	for _, id in ipairs(NS.SortedKeys(NS.db.ignoredNPCs)) do
		NS.Print(L["Ignored NPC: %s (%s)"], tostring(NS.db.ignoredNPCs[id]), tostring(id))
		any = true
	end
	for _, id in ipairs(NS.SortedKeys(NS.db.ignoredQuests)) do
		NS.Print(L["Ignored quest: %s (%s)"], tostring(NS.db.ignoredQuests[id]), tostring(id))
		any = true
	end
	if not any then NS.Print(L["Nothing is ignored."]) end
end

function Auto.PrintContext()
	local guid = Auto.NPCGUID()
	local npcID = Auto.NPCID(guid)
	if npcID then
		NS.Print(L["NPC in front of you: %s (%d)%s"], tostring(Auto.NPCName() or "?"), npcID,
			NS.db.ignoredNPCs[npcID] and (" - " .. L["ignored"]) or "")
	end
	local why = Auto.Blocked()
	if why == "modifier" then
		NS.Print(L["The pause key is held: this interaction stays manual."])
	elseif why == "interaction" then
		NS.Print(L["This interaction stays manual (the pause key was held when it began)."])
	elseif why == "npc" then
		NS.Print(L["This NPC is on the ignore list."])
	end
	local c = NS.chardb.counts
	NS.Print(L["This character: %d quests accepted, %d handed in, %d rewards chosen, %d left to you."],
		c.accepted, c.turnedIn, c.chosen, c.left)
end

function Auto.DebugReport()
	NS.Print("Automation: stage %s, session paused %s, pausedNPC %s, pending %s, waiting for %s, ignored NPCs %d, ignored quests %d",
		tostring(state.stage), tostring(state.sessionPaused), tostring(state.pausedNPC),
		state.pending and (tostring(state.pending.questID) .. "#" .. state.pending.attempt) or "none",
		state.waiting and tostring(state.waiting.questID) or "nothing",
		#NS.SortedKeys(NS.db.ignoredNPCs), #NS.SortedKeys(NS.db.ignoredQuests))
end

--------------------------------------------------------------------------------
-- Events.
--------------------------------------------------------------------------------
NS.RegisterEvent("GOSSIP_SHOW", Auto.OnGossipShow)
NS.RegisterEvent("GOSSIP_CLOSED", Auto.OnGossipClosed)
NS.RegisterEvent("QUEST_GREETING", Auto.OnQuestGreeting)
NS.RegisterEvent("QUEST_DETAIL", Auto.OnQuestDetail)
NS.RegisterEvent("QUEST_PROGRESS", Auto.OnQuestProgress)
NS.RegisterEvent("QUEST_COMPLETE", Auto.OnQuestComplete)
NS.RegisterEvent("QUEST_ITEM_UPDATE", Auto.OnQuestItemUpdate)
NS.RegisterEvent("QUEST_FINISHED", Auto.OnQuestFinished)
NS.RegisterEvent("QUEST_ACCEPTED", Auto.OnQuestAccepted)
NS.RegisterEvent("QUEST_TURNED_IN", Auto.OnQuestTurnedIn)
NS.RegisterEvent("QUEST_ACCEPT_CONFIRM", Auto.OnAcceptConfirm)
