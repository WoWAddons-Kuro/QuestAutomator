-- QuestAutomator: the pre-pick window (spec §6.4). When a quest is accepted whose
-- reward choice the engine would only recommend (a trinket, a rare, several
-- upgrades...), the choices are shown right away so the player can decide while
-- the quest text is fresh. The pick is remembered per character by quest ID and
-- *item ID* (never by index, so a reordered reward list cannot misfire) and turns
-- the hand-in into an automatic one. Cleared when the quest is handed in or dropped.
--
-- The window reads the quest log's reward list for the accepted quest through the
-- client adapter (Rewards.LogSource) a moment after QUEST_ACCEPTED, when the log
-- entry exists. Nothing is written into Blizzard's frames.
local ADDON, NS = ...
local L = NS.L
local Rules, Rewards, Engine = NS.Rules, NS.Rewards, NS.Engine
local PrePick = {}
NS.PrePick = PrePick

PrePick.FRAME_NAME = "QuestAutomatorPrePickFrame"
PrePick.ICON_SIZE = 36
PrePick.ROW_HEIGHT = 64        -- icon + name line + two stat-delta lines
PrePick.WIDTH = 360
PrePick.STAT_COLS = 2          -- stat deltas laid out in this many columns
PrePick.OPEN_DELAY = 0.3   -- seconds after QUEST_ACCEPTED before the log is read
PrePick.MAX_LOAD_TRIES = 6
PrePick.RETRY_DELAY = 0.5

local frame, rows = nil, {}
local state = { questID = nil, choices = nil, decision = nil, attempt = 0 }
PrePick.state = state

--------------------------------------------------------------------------------
-- Storage: chardb.prePicks[questID] = itemID
--------------------------------------------------------------------------------
function PrePick.Get(questID)
	local store = NS.chardb and NS.chardb.prePicks
	return store and questID and store[questID] or nil
end

function PrePick.Set(questID, itemID)
	local store = NS.chardb and NS.chardb.prePicks
	if not store or not questID then return end
	store[questID] = itemID
end

function PrePick.Clear(questID)
	local store = NS.chardb and NS.chardb.prePicks
	if store and questID then store[questID] = nil end
end

-- Window position, account-wide: settings.prePickPos = { point, x, y }.
function PrePick.SavePosition()
	if not frame or not NS.db then return end
	local point, _, _, x, y = frame:GetPoint(1)
	if point then NS.db.settings.prePickPos = { point = point, x = x, y = y } end
end

function PrePick.RestorePosition()
	if not frame then return end
	frame:ClearAllPoints()
	local pos = NS.db and NS.db.settings.prePickPos
	if type(pos) == "table" and pos.point then
		frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
end

--------------------------------------------------------------------------------
-- The frame.
--------------------------------------------------------------------------------
local function BuildFrame()
	local f = CreateFrame("Frame", PrePick.FRAME_NAME, UIParent, "BackdropTemplate")
	f:SetSize(PrePick.WIDTH, 120)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	-- Dragging only while unlocked (preview mode), so a hurried click at hand-in
	-- cannot move the window by accident. Position is kept in settings.prePickPos.
	f:SetScript("OnDragStart", function(self) if NS.db.settings.prePickUnlocked then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); PrePick.SavePosition() end)
	f:SetClampedToScreen(true)
	frame = f
	PrePick.RestorePosition()
	if f.SetBackdrop then
		-- The plain tooltip nine-slice (what the settings sections and KondoBags use),
		-- not the bolted dialog border.
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		f:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
		f:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
	end

	f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Title:SetPoint("TOP", f, "TOP", 0, -10)
	f.Title:SetWidth(PrePick.WIDTH - 40)
	f.Title:SetJustifyH("CENTER")

	f.Reason = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Reason:SetPoint("TOP", f.Title, "BOTTOM", 0, -3)
	f.Reason:SetWidth(PrePick.WIDTH - 40)
	f.Reason:SetJustifyH("CENTER")

	f.Close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.Close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
	f.Close:SetScript("OnClick", function() PrePick.Dismiss() end)

	f.Later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Later:SetSize(120, 22)
	f.Later:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
	f.Later:SetText(L["Decide at hand-in"])
	f.Later:SetScript("OnClick", function() PrePick.Dismiss() end)

	f:Hide()
	return f
end

local function BuildRow(index)
	local row = CreateFrame("Button", nil, frame)
	row:SetSize(PrePick.WIDTH - 40, PrePick.ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(PrePick.ICON_SIZE, PrePick.ICON_SIZE)
	row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	row.Border = row:CreateTexture(nil, "OVERLAY")
	row.Border:SetSize(PrePick.ICON_SIZE * 1.7, PrePick.ICON_SIZE * 1.7)
	row.Border:SetPoint("CENTER", row.Icon, "CENTER", 0, 0)
	row.Border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	row.Border:SetBlendMode("ADD")
	row.Border:SetVertexColor(1, 0.85, 0.3)
	row.Border:Hide()

	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -2)
	row.Name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.Name:SetJustifyH("LEFT")

	-- Stat delta grid under the name: STAT_COLS columns of fixed-width cells, each
	-- three font strings in fixed sub-columns so the numbers line up down the rows:
	--   [label, left][value, RIGHT, wide enough for "999"][delta, left, wide enough for "+999"]
	-- Widths are measured once from the font so they hold on any UI scale / locale.
	row.Cells = {}
	local colW = math.floor((PrePick.WIDTH - 40 - PrePick.ICON_SIZE - 8) / PrePick.STAT_COLS)
	local measure = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	measure:SetText("999")
	local valueW = math.ceil(measure:GetStringWidth()) + 2
	measure:SetText("+999")
	local deltaW = math.ceil(measure:GetStringWidth()) + 2
	measure:Hide()
	local gap = 4
	local labelW = colW - valueW - deltaW - 2 * gap - 6
	for i = 1, PrePick.STAT_COLS * 2 do
		local col, line = (i - 1) % PrePick.STAT_COLS, math.floor((i - 1) / PrePick.STAT_COLS)
		local x, y = col * colW, -2 - line * 13
		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", x, y)
		label:SetSize(labelW, 12)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		label:SetTextColor(0.69, 0.69, 0.69)
		local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("TOPLEFT", label, "TOPRIGHT", gap, 0)
		value:SetSize(valueW, 12)
		value:SetJustifyH("RIGHT")
		local delta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		delta:SetPoint("TOPLEFT", value, "TOPRIGHT", gap, 0)
		delta:SetSize(deltaW, 12)
		delta:SetJustifyH("LEFT")
		row.Cells[i] = { label = label, value = value, delta = delta }
	end
	-- Hidden alternative when there is nothing to compare: the engine's reason text.
	row.Info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Info:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -2)
	row.Info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.Info:SetJustifyH("LEFT")

	row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.Highlight:SetAllPoints(row)
	row.Highlight:SetColorTexture(1, 1, 1, 0.08)

	row:SetScript("OnClick", function(self) PrePick.Choose(self.choice) end)
	row:SetScript("OnEnter", function(self)
		PrePick.ShowTooltip(self)
	end)
	row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	return row
end

local function Row(index)
	if not rows[index] then rows[index] = BuildRow(index) end
	return rows[index]
end

local function IconFor(c)
	local ref = c.link or c.itemID
	if not ref then return "Interface\\Icons\\INV_Misc_QuestionMark" end
	local _, _, _, _, icon = NS.Call("C_Item.GetItemInfoInstant", ref)
	return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

--------------------------------------------------------------------------------
-- Tooltip: the full item tooltip (quest-log item when the choice came from the
-- log, so it shows the "Currently equipped" comparison; the hyperlink otherwise).
--------------------------------------------------------------------------------
function PrePick.ShowTooltip(row)
	local c = row.choice
	if not c or not GameTooltip then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local shown = false
	if state.source and state.source.name == "log" and not state.preview and GameTooltip.SetQuestLogItem then
		-- Era / Forever both take ("choice", index) for the selected log quest.
		shown = pcall(GameTooltip.SetQuestLogItem, GameTooltip, "choice", c.index)
	end
	if not shown and c.link then
		GameTooltip:SetHyperlink(c.link)
		shown = true
	end
	if not shown then
		GameTooltip:SetText(c.name or "?")
	end
	if GameTooltip_ShowCompareItem and not state.preview then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Stat deltas: { { label, value, delta } ... }, item level first, then the stats
-- the class weights care about (heaviest first), each against the worn piece.
-- Sample rows carry a ready-made list in c.sampleDeltas.
--------------------------------------------------------------------------------
local function WornStats(c)
	local link = c.worn and c.worn.link
	if not link then return {} end
	return NS.Client.ItemStats(link) or Rewards.StatsFromTooltipData(nil) or {}
end

function PrePick.StatDeltas(c, player)
	if c.sampleDeltas then return c.sampleDeltas end
	local out = {}
	local wornLevel = c.worn and c.worn.itemLevel or nil
	out[#out + 1] = { label = L["ilevel"], value = c.itemLevel or 0, delta = wornLevel and ((c.itemLevel or 0) - wornLevel) or nil }
	local worn = WornStats(c)
	local keys = {}
	for key, amount in pairs(c.stats or {}) do if amount ~= 0 then keys[#keys + 1] = key end end
	for key, amount in pairs(worn) do
		if amount ~= 0 and not (c.stats and c.stats[key]) then keys[#keys + 1] = key end
	end
	local weights = player and player.weights or {}
	table.sort(keys, function(a, b)
		local wa, wb = weights[a] or 0, weights[b] or 0
		if wa ~= wb then return wa > wb end
		return a < b
	end)
	for _, key in ipairs(keys) do
		local mine = c.stats and c.stats[key] or 0
		local theirs = worn[key]
		out[#out + 1] = { label = Rules.StatName(key), value = mine, delta = (c.worn and c.worn.link) and (mine - (theirs or 0)) or nil }
	end
	return out
end

local function FormatDelta(d)
	if d == nil then return "" end
	if d > 0 then return string.format(" |cff40ff40+%d|r", d) end
	if d < 0 then return string.format(" |cffff4040%d|r", d) end
	return " |cff808080=|r"
end

local function FormatValue(v)
	if type(v) == "number" and v ~= math.floor(v) then return string.format("%.1f", v) end
	return tostring(v)
end

-- Fills one three-part cell; hides it when there is no entry.
local function FillCell(cell, entry)
	if not entry then
		cell.label:Hide(); cell.value:Hide(); cell.delta:Hide()
		return
	end
	cell.label:SetText(tostring(entry.label))
	cell.value:SetText(FormatValue(entry.value))
	cell.delta:SetText((FormatDelta(entry.delta):gsub("^ ", "")))
	cell.label:Show(); cell.value:Show(); cell.delta:Show()
end

-- One-string form (chat / debug).
local function FormatCell(entry)
	if not entry then return "" end
	return string.format("|cffb0b0b0%s|r %s%s", tostring(entry.label), FormatValue(entry.value), FormatDelta(entry.delta))
end

--------------------------------------------------------------------------------
-- Show / hide.
--------------------------------------------------------------------------------
function PrePick.Hide()
	if frame then frame:Hide() end
	state.questID, state.choices, state.decision, state.preview = nil, nil, nil, nil
	state.source = nil
end

-- The close box and "Decide at hand-in": in preview mode they also untick the
-- unlock setting, so the window locks and goes away without a trip to the settings.
function PrePick.Dismiss()
	if state.preview and NS.db then
		NS.db.settings.prePickUnlocked = false
		NS.OnSettingsChanged()
		if NS.RefreshSettingsPage then NS.RefreshSettingsPage() end
	end
	PrePick.Hide()
end

-- Lays the current state out. Called by Open and when a pick changes.
function PrePick.Render()
	if not frame or not state.questID or not state.choices then return end
	local title = state.preview and L["Sample quest"] or (NS.Client.QuestTitle(state.questID) or ("#" .. state.questID))
	frame.Title:SetText(string.format(L["Reward for %s"], title))
	local decision = state.decision
	if state.preview then
		frame.Reason:SetText(L["Preview: drag me into place, then untick the setting to lock."])
	else
		frame.Reason:SetText(decision and Engine.LeaveReasonText(decision) or "")
	end
	local picked = PrePick.Get(state.questID)
	local player = not state.preview and Rules.Player() or nil
	local y = -52
	local shown = 0
	for i, c in ipairs(state.choices) do
		if c.lootType == Rewards.LOOT_ITEM then
			shown = shown + 1
			local row = Row(shown)
			row.choice = c
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y)
			row.Icon:SetTexture((c.icon or IconFor(c)))
			local colors = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[c.quality or 1]
			local hex = colors and colors.hex or "|cffffffff"
			local isPicked = picked ~= nil and c.itemID == picked
			local isSuggested = decision and decision.index == c.index
			row.Name:SetText(hex .. (c.name or "?") .. "|r" .. (isPicked and (" |cff40ff40" .. L["(your pick)"] .. "|r") or (isSuggested and (" |cffffd100" .. L["(suggested)"] .. "|r") or "")))
			-- Stat grid when the item is wearable (there is something to compare); the
			-- engine's reason line otherwise (hard to value, cannot wear...).
			local deltas = c.wearable and PrePick.StatDeltas(c, player) or nil
			if deltas and #deltas > 0 then
				for j, cell in ipairs(row.Cells) do FillCell(cell, deltas[j]) end
				row.Info:Hide()
			else
				for _, cell in ipairs(row.Cells) do FillCell(cell, nil) end
				row.Info:SetText(Engine.ItemReasonText(c))
				row.Info:Show()
			end
			row.Border:SetShown(isPicked or (picked == nil and isSuggested))
			row:Show()
			y = y - PrePick.ROW_HEIGHT
		end
	end
	for i = shown + 1, #rows do rows[i]:Hide() end
	frame:SetHeight(-y + 40)
	frame:Show()
end

-- The player clicked a reward: remember it (toggle off when clicked again).
function PrePick.Choose(c)
	if not c or not state.questID then return end
	if state.preview then return end
	if PrePick.Get(state.questID) == c.itemID then
		PrePick.Clear(state.questID)
		NS.Print(L["Pre-pick cleared for %s."], NS.Client.QuestTitle(state.questID) or state.questID)
	else
		PrePick.Set(state.questID, c.itemID)
		NS.Print(L["Pre-pick for %s: %s. It will be taken automatically at hand-in."], NS.Client.QuestTitle(state.questID) or state.questID, Rewards.ChoiceLabel(c))
		PrePick.Render()
		NS.After(0.6, function() if state.questID then PrePick.Hide() end end)
		return
	end
	PrePick.Render()
end

-- Evaluates the log rewards of questID; opens the window when the engine would only
--------------------------------------------------------------------------------
-- Preview (unlocked) mode: the settings checkbox "Unlock and show the pick window"
-- shows the window with sample rows so the player can drag it into place. No quest
-- is involved: clicks do nothing, the title says so, and hiding it re-locks.
--------------------------------------------------------------------------------
local SAMPLE_ROWS = {
	{ index = 1, lootType = 0, name = "Sample Sword", quality = 2, itemLevel = 22, loaded = true, wearable = true, worn = { itemLevel = 18 }, delta = 4, isUpgrade = true, hardToValue = false, icon = "Interface\\Icons\\INV_Sword_04",
		sampleDeltas = { { label = "ilevel", value = 22, delta = 4 }, { label = "Intellect", value = 12, delta = -3 }, { label = "Strength", value = 18, delta = 1 }, { label = "Stamina", value = 9, delta = 0 } } },
	{ index = 2, lootType = 0, name = "Sample Trinket", quality = 3, itemLevel = 22, loaded = true, wearable = false, hardToValue = true, hardReason = "trinket", icon = "Interface\\Icons\\INV_Misc_OrbOfDeception" },
	{ index = 3, lootType = 0, name = "Sample Cloak", quality = 2, itemLevel = 20, loaded = true, wearable = true, worn = { itemLevel = 20 }, delta = 0, isSidegrade = true, hardToValue = false, icon = "Interface\\Icons\\INV_Misc_Cape_11",
		sampleDeltas = { { label = "ilevel", value = 20, delta = 0 }, { label = "Agility", value = 6, delta = 2 }, { label = "Armor", value = 24, delta = -5 } } },
}

function PrePick.SetUnlocked(unlocked)
	if unlocked then
		if not frame then frame = BuildFrame() end
		state.questID, state.choices, state.preview = -1, SAMPLE_ROWS, true
		state.decision = { tier = "1", action = "recommend", index = 1, reason = "trinket" }
		PrePick.Render()
	elseif state.preview then
		PrePick.Hide()
	end
end

-- When the settings page sets the flag directly (slash, reload), follow it.
NS.RegisterEvent("PLAYER_LOGIN", function()
	if NS.db and NS.db.settings.prePickUnlocked then
		NS.After(1, function() PrePick.SetUnlocked(true) end)
	end
end)

-- Evaluates the log rewards of questID; opens the window when the engine would only
-- recommend (or when force is set, e.g. /qam pick). Retries while item data loads.
function PrePick.Open(questID, force, attempt)
	attempt = attempt or 1
	if not NS.db or not questID then return false end
	local source = Rewards.LogSource(questID)
	local n = NS.SafeNumber(source.Count()) or 0
	if n < 2 then
		if force then NS.Print(L["%s has no reward to choose."], NS.Client.QuestTitle(questID) or questID) end
		return false
	end
	local choices = Rewards.Gather(n, source)
	local decision = Rewards.Evaluate(choices, NS.db.settings, Rules.Player())
	if decision.pending then
		if attempt >= PrePick.MAX_LOAD_TRIES then return false end
		for _, c in ipairs(choices) do
			if c.loaded == false and c.itemID then NS.Call("C_Item.RequestLoadItemDataByID", c.itemID) end
		end
		NS.After(PrePick.RETRY_DELAY, function() PrePick.Open(questID, force, attempt + 1) end)
		return false
	end
	if not force and (decision.action == "auto" or not decision.index) then return false end
	if not frame then frame = BuildFrame() end
	state.questID, state.choices, state.decision, state.source = questID, choices, decision, source
	PrePick.Render()
	return true
end

--------------------------------------------------------------------------------
-- Events and command.
--------------------------------------------------------------------------------
NS.RegisterEvent("QUEST_ACCEPTED", function(a, b)
	if not NS.loaded or not NS.db.settings.prePickUI or not NS.db.settings.enabled then return end
	-- Forever passes questID first; Era passes questIndex, questID (QuestLogDocumentation).
	local questID = NS.SafeNumber(b) or NS.SafeNumber(a)
	if not questID or questID <= 0 then return end
	NS.After(PrePick.OPEN_DELAY, function() PrePick.Open(questID, false) end)
end)

local function Forget(questID)
	questID = NS.SafeNumber(questID)
	if not questID then return end
	PrePick.Clear(questID)
	if state.questID == questID then PrePick.Hide() end
end
NS.RegisterEvent("QUEST_TURNED_IN", Forget)
NS.RegisterEvent("QUEST_REMOVED", Forget)

-- /qam pick [questID]: open for the given quest, else the one selected in the log.
function PrePick.Command(rest)
	local questID = tonumber(rest)
	if not questID then
		local ctx = NS.Client.RewardContext()
		questID = ctx and ctx.questID
	end
	if not questID then
		NS.Print(L["Select a quest in the log (or give its ID), then /qam pick."])
		return
	end
	PrePick.Open(questID, true)
end

function PrePick.DebugReport()
	local store = NS.chardb and NS.chardb.prePicks or {}
	NS.Print("Pre-picks: %d stored, window %s for %s", #NS.SortedKeys(store), frame and frame:IsShown() and "shown" or "hidden", tostring(state.questID))
end