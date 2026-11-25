-- QuestAutomator: pre-pick view and UI interactions. PrePickData reads display
-- snapshots; PrePickModel owns selections; TurnInResolver owns consumption.
-- No quest-dialog eligibility or hand-in function is changed by this module.
local ADDON, NS = ...
local L = NS.L
local Rules, Rewards = NS.Rules, NS.Rewards
local Data = NS.PrePickData
local Model = NS.PrePickModel
local PrePick = {}
NS.PrePick = PrePick

PrePick.FRAME_NAME = "QuestAutomatorPrePickFrame"
PrePick.ICON_SIZE = 36
PrePick.ROW_HEIGHT = 54        -- minimum: name line (14) + 2 grid lines (13 each) + spacing
PrePick.GRID_LINE_HEIGHT = 13  -- one line of the stat grid
PrePick.ROW_GAP = 10           -- space between cards (the card border overhangs 3-4px)
PrePick.WIDTH = 360
PrePick.STAT_COLS = 2          -- stat deltas laid out in this many columns
PrePick.LIST_LINE_HEIGHT = 16  -- one line per pending quest in the quest list
PrePick.OPEN_DELAY = 0.3   -- seconds after QUEST_ACCEPTED before the log is read
PrePick.MAX_LOAD_TRIES = 6
PrePick.RETRY_DELAY = 0.5
-- Marker badges on the item icon's corners (and inline in the legend): the engine's
-- recommendation (gold coin, upper-left) and the player's stored pre-pick (green
-- check, upper-right).
PrePick.TEXTURE_RECOMMENDED = "Interface\\Buttons\\UI-GroupLoot-Coin-Up"
PrePick.TEXTURE_PICKED = "Interface\\RaidFrame\\ReadyCheck-Ready"
PrePick.ICON_RECOMMENDED = "|T" .. PrePick.TEXTURE_RECOMMENDED .. ":0|t"
PrePick.ICON_PICKED = "|T" .. PrePick.TEXTURE_PICKED .. ":0|t"
PrePick.BADGE_SIZE = 16
PrePick.MATERIAL_SIZE = 14     -- armour-material reagent badge, lower-right of the icon

local frame, rows, questLines = nil, {}, {}
local state = { questID = nil, choices = nil, decision = nil, attempt = 0 }
PrePick.state = state

--------------------------------------------------------------------------------
-- Storage: chardb.prePicks[questID] = itemID
--------------------------------------------------------------------------------
function PrePick.Get(questID)
	return Model.GetSelectedRewardItemID(questID)
end

function PrePick.Set(questID, itemID)
	return Model.SetSelectedRewardItemID(questID, itemID)
end

function PrePick.Clear(questID)
	return Model.ClearSelection(questID)
end

--------------------------------------------------------------------------------
-- Pending quests: every log quest with two or more item choices, i.e. a reward
-- decision that will be made at hand-in. Each entry says whether the player has
-- already pre-picked (picked = itemID) and whether the engine would decide on its
-- own (auto) or wants the player (recommend). Used by the window's quest list and
-- the minimap tooltip.
--   -> list of { questID, title, choiceCount, picked, action, pending }
-- Gathering reads every choice's item data, so the list is cached for a moment
-- (Render and the tooltip may ask several times in one frame).
--------------------------------------------------------------------------------
PrePick.PENDING_CACHE_SECONDS = 0.5
local pendingCache = { at = -1, list = {}, selectionRevision = -1 }
function PrePick.PendingQuests()
	if not NS.loaded then return {} end
	local now = NS.Now()
	if now - pendingCache.at < PrePick.PENDING_CACHE_SECONDS and pendingCache.selectionRevision == Model.GetRevision() then
		return pendingCache.list
	end
	local list = {}
	local player = Rules.Player()
	for _, entry in ipairs(Data.ListQuests()) do
		local source = Data.LogSource(entry.questID)
		local n = NS.SafeNumber(source.Count()) or 0
		if n >= 2 then
			local item = { questID = entry.questID, title = entry.title, choiceCount = n, picked = PrePick.Get(entry.questID) }
			local choices = Rewards.Gather(n, source)
			local decision = Data.Evaluate(choices, NS.db.settings, player, entry.questID)
			item.pending = decision.pending == true
			item.action = decision.action
			item.prePickStatus = decision.prePickStatus
			list[#list + 1] = item
		end
	end
	pendingCache.at, pendingCache.list = now, list
	pendingCache.selectionRevision = Model.GetRevision()
	return list
end

-- Drops the cache (a pick was made, a quest came or went).
function PrePick.InvalidatePending()
	pendingCache.at = -1
end

function PrePick.StatusText(quest)
	if quest.pending then return L["item data not loaded"] end
	if quest.prePickStatus == "matched" then return L["(your pick)"] end
	if quest.picked then return L["(pick unavailable)"] end
	return quest.action == "auto" and L["(auto)"] or L["(decide)"]
end

-- Opens the window on the first pending quest that needs the player (else the
-- first pending quest at all). False when the log holds no quest with a choice.
function PrePick.OpenAny()
	if state.preview then PrePick.Dismiss() end
	local pending = PrePick.PendingQuests()
	if #pending == 0 then return PrePick.ShowEmpty() end
	local target = pending[1]
	for _, q in ipairs(pending) do
		if not q.picked and q.action ~= "auto" then target = q; break end
	end
	if state.questID and frame and frame:IsShown() then
		for _, q in ipairs(pending) do
			if q.questID == state.questID then target = q; break end
		end
	end
	return PrePick.Open(target.questID, true)
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

	f.Notice = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Notice:SetPoint("TOP", f.Title, "BOTTOM", 0, -4)
	f.Notice:SetWidth(PrePick.WIDTH - 40)
	f.Notice:SetJustifyH("CENTER")
	f.Notice:SetTextColor(1, 0.65, 0.2)

	-- "Stat profile: Shaman Enhancement v" - click for the profile popup. Centred
	-- under the notice; Render folds its height into the header when it is shown.
	if NS.ProfileSwitch then
		f.Profile = NS.ProfileSwitch.Create(f, "label")
		f.Profile:SetPoint("TOP", f.Notice, "BOTTOM", 0, -4)
		f.Profile:Hide()
	end

	f.Close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.Close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
	f.Close:SetScript("OnClick", function() PrePick.Dismiss() end)

	-- Foot, bottom-up (Render anchors these; each row takes height only when shown):
	--
	--   [ reward cards ]
	--   coin recommended   check your pick     <- Legend
	--   no item upgrade, most valuable: ...    <- Reason
	--   preselect an item now to ...           <- Hint (orange, decide quest w/o pick)
	--                               [ Next > ] <- Next ("Next" while a later quest says decide, else "Close")
	f.Next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.Next:SetSize(90, 22)
	f.Next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)
	f.Next:SetText(L["Next"])
	f.Next:SetScript("OnClick", function(self)
		if self.questID then PrePick.Open(self.questID, true) else PrePick.Dismiss() end
	end)

	f.Hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
	f.Hint:SetWidth(PrePick.WIDTH - 40)
	f.Hint:SetJustifyH("CENTER")
	f.Hint:SetTextColor(1, 0.65, 0.2)
	f.Hint:SetText(L["Pre-select an item now to automate the quest turn-in."])
	f.Hint:Hide()

	f.Reason = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Reason:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
	f.Reason:SetWidth(PrePick.WIDTH - 40)
	f.Reason:SetJustifyH("CENTER")
	f.Reason:SetTextColor(1, 0.82, 0)

	f.Legend = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Legend:SetPoint("BOTTOM", f.Reason, "TOP", 0, 6)
	f.Legend:SetWidth(PrePick.WIDTH - 40)
	f.Legend:SetJustifyH("CENTER")
	f.Legend:SetTextColor(0.69, 0.69, 0.69)
	f.Legend:SetText(PrePick.ICON_RECOMMENDED .. " " .. L["recommended"] .. "     " .. PrePick.ICON_PICKED .. " " .. L["your pick"])

	-- Quest list: one line per pending quest, under the reason line; the shown
	-- quest is highlighted, clicking another switches the rows to it. Hidden when
	-- only one quest is pending (the title already names it).
	f.List = CreateFrame("Frame", nil, f)
	f.List:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -46)
	f.List:SetPoint("RIGHT", f, "RIGHT", -20, 0)
	f.List:SetHeight(1)
	f.List:Hide()

	f:Hide()
	return f
end

local function BuildQuestLine(index)
	local line = CreateFrame("Button", nil, frame.List)
	line:SetHeight(PrePick.LIST_LINE_HEIGHT)
	line:SetPoint("LEFT", frame.List, "LEFT", 0, 0)
	line:SetPoint("RIGHT", frame.List, "RIGHT", 0, 0)
	line.Text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	line.Text:SetPoint("LEFT", line, "LEFT", 4, 0)
	line.Text:SetPoint("RIGHT", line, "RIGHT", -4, 0)
	line.Text:SetJustifyH("LEFT")
	line.Text:SetWordWrap(false)
	line.Current = line:CreateTexture(nil, "BACKGROUND")
	line.Current:SetAllPoints(line)
	line.Current:SetColorTexture(1, 0.85, 0.3, 0.15)
	line.Current:Hide()
	local hl = line:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(line)
	hl:SetColorTexture(1, 1, 1, 0.08)
	line:SetScript("OnClick", function(self)
		if self.questID and self.questID ~= state.questID then PrePick.Open(self.questID, true) end
	end)
	return line
end

local function QuestLine(index)
	if not questLines[index] then questLines[index] = BuildQuestLine(index) end
	return questLines[index]
end

local function BuildRow(index)
	local row = CreateFrame("Button", nil, frame)
	row:SetSize(PrePick.WIDTH - 40, PrePick.ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(PrePick.ICON_SIZE, PrePick.ICON_SIZE)
	row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- Marker badges on the item icon: recommended (gold coin) upper-left, your pick
	-- (green check) upper-right. Textures, not inline text, so a long name cannot
	-- push them out of view.
	row.Recommended = row:CreateTexture(nil, "OVERLAY", nil, 2)
	row.Recommended:SetSize(PrePick.BADGE_SIZE, PrePick.BADGE_SIZE)
	row.Recommended:SetPoint("TOPLEFT", row.Icon, "TOPLEFT", -3, 3)
	row.Recommended:SetTexture(PrePick.TEXTURE_RECOMMENDED)
	row.Recommended:Hide()
	row.Picked = row:CreateTexture(nil, "OVERLAY", nil, 2)
	row.Picked:SetSize(PrePick.BADGE_SIZE, PrePick.BADGE_SIZE)
	row.Picked:SetPoint("TOPRIGHT", row.Icon, "TOPRIGHT", 3, 3)
	row.Picked:SetTexture(PrePick.TEXTURE_PICKED)
	row.Picked:Hide()
	-- Armour material (reagent icon) lower-right, on a dark square so it stays
	-- readable over a busy item icon. Texture set per row in Render.
	row.MaterialBack = row:CreateTexture(nil, "OVERLAY", nil, 1)
	row.MaterialBack:SetSize(PrePick.MATERIAL_SIZE + 2, PrePick.MATERIAL_SIZE + 2)
	row.MaterialBack:SetPoint("BOTTOMRIGHT", row.Icon, "BOTTOMRIGHT", 1, -1)
	row.MaterialBack:SetColorTexture(0, 0, 0, 0.85)
	row.MaterialBack:Hide()
	row.Material = row:CreateTexture(nil, "OVERLAY", nil, 2)
	row.Material:SetSize(PrePick.MATERIAL_SIZE, PrePick.MATERIAL_SIZE)
	row.Material:SetPoint("CENTER", row.MaterialBack, "CENTER", 0, 0)
	row.Material:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.Material:Hide()


	-- Suggested / picked marker: a yellow glow border around the whole card.
	row.Border = CreateFrame("Frame", nil, row, BackdropTemplateMixin and "BackdropTemplate" or nil)
	row.Border:SetPoint("TOPLEFT", row, "TOPLEFT", -4, 3)
	row.Border:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 4, -1)
	row.Border:SetFrameLevel(row:GetFrameLevel())
	if row.Border.SetBackdrop then
		row.Border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, bgFile = "Interface\\Buttons\\WHITE8x8", insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		row.Border:SetBackdropColor(1, 0.85, 0.3, 0.08)
		row.Border:SetBackdropBorderColor(1, 0.85, 0.3, 0.9)
	end
	row.Border:Hide()

	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Name:SetPoint("TOPLEFT", row, "TOPLEFT", PrePick.ICON_SIZE + 8, 0)
	row.Name:SetHeight(14)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)
	-- Name line: name (left) | vendor value | ilvl (right), the latter two in the
	-- small font, each a fixed sideW wide and packed against the right edge so the
	-- name gets everything left over and the columns line up on every row.
	local nameLeft = PrePick.ICON_SIZE + 8
	local lineW = PrePick.WIDTH - 40 - nameLeft - 4
	local sideW = math.floor(lineW * 0.20)
	row.Name:SetWidth(lineW - 2 * sideW - 4)
	row.Value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Value:SetPoint("TOP", row, "TOP", 0, -1)
	row.Value:SetPoint("RIGHT", row, "RIGHT", -4 - sideW, 0)
	row.Value:SetSize(sideW, 12)
	row.Value:SetJustifyH("RIGHT")
	row.Level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Level:SetPoint("TOP", row, "TOP", 0, -1)
	row.Level:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.Level:SetSize(sideW, 12)
	row.Level:SetJustifyH("RIGHT")

	-- Stat delta grid under the name: STAT_COLS columns, each a fixed layout of
	--   [label cell ................][value cell][delta cell]
	-- Every sub-cell is anchored to the ROW at a fixed x, never to its neighbour, so
	-- the value and delta columns sit in the same place on every line regardless of
	-- label length. Value is right-justified and sized for "999"; delta is left-
	-- justified and sized for "+999"; the label takes what is left and clips.
	row.Cells = {}
	local gridLeft = PrePick.ICON_SIZE + 8
	local colW = math.floor((PrePick.WIDTH - 40 - gridLeft) / PrePick.STAT_COLS)
	local measure = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	measure:SetText("999")
	local valueW = math.ceil(measure:GetStringWidth()) + 2
	measure:SetText("+999")
	local deltaW = math.ceil(measure:GetStringWidth()) + 2
	measure:Hide()
	local gap = 4
	local labelW = colW - valueW - deltaW - 2 * gap - 8
	-- Rows of the grid hang off the Name's bottom edge (so they always clear it);
	-- only the x offsets are fixed against the row. Cells are created on demand
	-- (PrePick.Cell) so a reward with many stats gets as many lines as it needs.
	local lineH = PrePick.GRID_LINE_HEIGHT
	row.gridLeft, row.colW, row.labelW, row.valueW, row.deltaW, row.gap = gridLeft, colW, labelW, valueW, deltaW, gap
	function row:MakeCell(i)
		local col, line = (i - 1) % PrePick.STAT_COLS, math.floor((i - 1) / PrePick.STAT_COLS)
		local x0 = gridLeft + col * colW
		local y = -3 - line * lineH
		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOP", row.Name, "BOTTOM", 0, y)
		label:SetPoint("LEFT", row, "LEFT", x0, 0)
		label:SetSize(labelW, 12)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		label:SetTextColor(0.69, 0.69, 0.69)
		local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("TOP", row.Name, "BOTTOM", 0, y)
		value:SetPoint("LEFT", row, "LEFT", x0 + labelW + gap, 0)
		value:SetSize(valueW, 12)
		value:SetJustifyH("RIGHT")
		local delta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		delta:SetPoint("TOP", row.Name, "BOTTOM", 0, y)
		delta:SetPoint("LEFT", row, "LEFT", x0 + labelW + gap + valueW + gap, 0)
		delta:SetSize(deltaW, 12)
		delta:SetJustifyH("LEFT")
		local cell = { label = label, value = value, delta = delta }
		row.Cells[i] = cell
		return cell
	end
	-- Hidden alternative when there is nothing to compare: the engine's reason text.
	row.Info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Info:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -2)
	row.Info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.Info:SetJustifyH("LEFT")
	-- Centred orange warning under the grid (untrained weapon).
	row.Warn = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Warn:SetPoint("LEFT", row, "LEFT", gridLeft, 0)
	row.Warn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.Warn:SetJustifyH("CENTER")
	row.Warn:SetTextColor(1, 0.6, 0.2)
	row.Warn:Hide()

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
-- Tooltip: the full item tooltip by hyperlink / itemID, plus the "Currently
-- equipped" comparison. Never SetQuestLogItem("choice", index): that reads the
-- *selected* log quest, which at accept time is rarely the one just taken.
--------------------------------------------------------------------------------
function PrePick.ShowTooltip(row)
	local c = row.choice
	if not c or not GameTooltip then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local shown = false
	if c.link then
		shown = pcall(GameTooltip.SetHyperlink, GameTooltip, c.link)
	end
	if not shown and c.itemID and GameTooltip.SetItemByID then
		shown = pcall(GameTooltip.SetItemByID, GameTooltip, c.itemID)
	end
	if not shown then
		GameTooltip:SetText(c.name or "?")
	end
	if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Stat deltas: { { label, value, delta } ... }, item level first, then the stats
-- the class weights care about (heaviest first), each against the worn piece.
--------------------------------------------------------------------------------
local function WornStats(c)
	local link = c.worn and c.worn.link
	if not link then return {} end
	return Data.ItemStats(link)
end

function PrePick.StatDeltas(c, player)
	local out = {}
	-- Item level lives on the name line (row.Level); the grid is stats only.
	local worn = WornStats(c)
	local wornKnown = worn ~= nil
	worn = worn or {}
	local keys = {}
	for key, amount in pairs(c.stats or {}) do if amount ~= 0 then keys[#keys + 1] = key end end
	for key, amount in pairs(worn) do
		if amount ~= 0 and (not c.stats or not c.stats[key] or c.stats[key] == 0) then keys[#keys + 1] = key end
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
		out[#out + 1] = { label = Rules.StatName(key), value = mine, delta = wornKnown and c.worn and (mine - (theirs or 0)) or nil }
	end
	return out
end

local function FormatDelta(d)
	if d == nil then return "" end
	if d > 0 then return " |cff40ff40" .. Rewards.FormatAmount(d) .. "|r" end
	if d < 0 then return " |cffff4040" .. Rewards.FormatAmount(d) .. "|r" end
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
	state.requestID = (state.requestID or 0) + 1
	if frame then frame:Hide() end
	if GameTooltip then GameTooltip:Hide() end
	state.questID, state.choices, state.decision, state.preview = nil, nil, nil, nil
	state.source = nil
end

function PrePick.ShowEmpty()
	if not frame then frame = BuildFrame() end
	state.requestID = (state.requestID or 0) + 1
	state.questID, state.choices, state.decision, state.preview = 0, {}, nil, false
	PrePick.Render()
	return true
end

-- The close box: in preview mode it also unticks the unlock setting, so the
-- window locks and goes away without a trip to the settings.
function PrePick.Dismiss()
	if state.preview and NS.db then
		NS.db.settings.prePickUnlocked = false
		NS.OnSettingsChanged()
		if NS.RefreshSettingsPage then NS.RefreshSettingsPage() end
	end
	PrePick.Hide()
end

-- Minimap action: closing cancels outstanding item-load callbacks as well.
function PrePick.Toggle()
	if frame and frame:IsShown() then
		PrePick.Dismiss()
		return false
	end
	return PrePick.OpenAny()
end

-- A stat-profile switch (from any switcher) re-scores the open window in place: the
-- coin, the "+N" deltas and the reason line all depend on the profile's weights.
-- Preview mode keeps its sample data; the empty window has nothing to score.
function PrePick.OnProfileChanged()
	if not frame or not frame:IsShown() or not state.questID or state.questID == 0 then
		if frame and frame.Profile then frame.Profile:Update() end
		return
	end
	if state.choices and not state.preview then
		state.decision = Data.Evaluate(state.choices, NS.db.settings, Rules.Player(), state.questID)
	end
	PrePick.Render()
end

-- Lays the current state out. Called by Open and when a pick changes.
function PrePick.Render()
	if not frame or not state.questID or not state.choices then return end
	local title = state.preview and L["Sample quest"] or (Data.QuestTitle(state.questID) or ("#" .. state.questID))
	if state.questID == 0 then title = L["Quest reward pre-selection"] end
	frame.Title:SetText(string.format(L["Reward for %s"], title))
	local decision = state.decision
	if state.preview then
		frame.Reason:SetText(L["Preview: drag me into place, then untick the setting to lock."])
	elseif state.questID == 0 then
		frame.Reason:SetText(L["No quest in your log has a reward to choose."])
	else
		frame.Reason:SetText(Data.DecisionText(decision))
	end
	frame.Notice:SetText(L["Pre-select your reward."])
	local picked = PrePick.Get(state.questID)
	local player = Rules.Player()
	-- Stat-profile switcher under the notice (SPECS/STAT_PROFILES.md). Hidden by the
	-- profileSwitchers setting; the header grows only when it is shown.
	local switcherHeight = 0
	if frame.Profile and frame.Profile:Update() then
		switcherHeight = frame.Profile:GetHeight() + 4
	end
	-- Quest list between the reason line and the rows: only with 2+ pending quests.
	local pending = (not state.preview) and PrePick.PendingQuests() or {}
	local headerHeight = 10 + frame.Title:GetStringHeight() + 4 + frame.Notice:GetStringHeight() + switcherHeight + 12
	frame.List:ClearAllPoints()
	frame.List:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -headerHeight)
	frame.List:SetWidth(PrePick.WIDTH - 40)
	local listHeight = 0
	if #pending >= 1 then
		for i, q in ipairs(pending) do
			local line = QuestLine(i)
			line.questID = q.questID
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", frame.List, "TOPLEFT", 0, -(i - 1) * PrePick.LIST_LINE_HEIGHT)
			line:SetPoint("RIGHT", frame.List, "RIGHT", 0, 0)
			local mark = PrePick.StatusText(q)
			line.Text:SetText(string.format("%s  %s", q.title or ("#" .. q.questID), mark))
			line.Current:SetShown(q.questID == state.questID)
			line:Show()
		end
		for i = #pending + 1, #questLines do questLines[i]:Hide() end
		listHeight = #pending * PrePick.LIST_LINE_HEIGHT + 6
		frame.List:SetHeight(listHeight)
		frame.List:Show()
	else
		for _, line in ipairs(questLines) do line:Hide() end
		frame.List:Hide()
	end
	local y = -headerHeight - listHeight - 6
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
			-- Name line: name left, vendor value right of centre, ilvl right. The
			-- recommended / your-pick badges sit on the item icon's corners.
			row.Name:SetText(hex .. (c.name or "?") .. "|r")
			row.Recommended:SetShown(isSuggested and true or false)
			row.Picked:SetShown(isPicked)
			-- Armour material badge (lower-right of the icon): cloth / leather / mail /
			-- plate only; dimmed when wearable but lighter than the class's best type.
			local material = c.classID == Rules.CLASS_ARMOR and Rules.ARMOR_BADGE_TEXTURES[c.subclassID] or nil
			if material then
				row.Material:SetTexture(material)
				local dim = c.fit and c.fit.lighter and 0.45 or 1
				row.Material:SetVertexColor(dim, dim, dim)
				row.Material:Show()
				row.MaterialBack:Show()
			else
				row.Material:Hide()
				row.MaterialBack:Hide()
			end
			row.Value:SetText(c.loaded == false and "" or NS.FormatMoney((c.sellPrice or 0) * (c.count or 1)))
			local wornLevel = c.worn and c.worn.itemLevel or nil
			row.Level:SetText(string.format("|cffb0b0b0%s|r %s%s", L["ilvl"], FormatValue(c.itemLevel or 0), FormatDelta(wornLevel and ((c.itemLevel or 0) - wornLevel) or nil)))
			-- Stat grid when the item is wearable (there is something to compare), as
			-- many lines as the stats need; the engine's reason line otherwise. The card
			-- grows to fit; an untrained weapon gets a centred warning under the grid.
			local deltas = c.wearable and PrePick.StatDeltas(c, player) or nil
			local gridLines = 0
			if deltas and #deltas > 0 then
				for j = 1, math.max(#deltas, #row.Cells) do
					FillCell(row.Cells[j] or row:MakeCell(j), deltas[j])
				end
				gridLines = math.ceil(#deltas / PrePick.STAT_COLS)
				row.Info:Hide()
			else
				for _, cell in ipairs(row.Cells) do FillCell(cell, nil) end
				row.Info:SetText(Data.ItemText(c))
				row.Info:Show()
				gridLines = 1
			end
			local height = 14 + 3 + gridLines * PrePick.GRID_LINE_HEIGHT
			if c.untrained and deltas and #deltas > 0 then
				-- Centred inside the card, one grid line below the last stat line.
				row.Warn:SetText(L["needs weapon training"])
				row.Warn:ClearAllPoints()
				row.Warn:SetPoint("LEFT", row, "LEFT", row.gridLeft, 0)
				row.Warn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
				row.Warn:SetPoint("TOP", row, "TOP", 0, -height - 2)
				row.Warn:SetHeight(PrePick.GRID_LINE_HEIGHT)
				row.Warn:Show()
				height = height + 2 + PrePick.GRID_LINE_HEIGHT
			else
				row.Warn:Hide()
			end
			height = math.max(PrePick.ROW_HEIGHT - PrePick.ROW_GAP, height + 2)
			row:SetHeight(height)
			row.Border:SetShown(isPicked or (picked == nil and isSuggested))
			row:Show()
			y = y - height - PrePick.ROW_GAP
		end
	end
	for i = shown + 1, #rows do rows[i]:Hide() end
	frame.Legend:SetShown(shown > 0)
	-- Foot, bottom-up: the Next / Close button row, optional orange hint, reason,
	-- legend. The button says Next while a later quest in the list still needs a
	-- decision, and Close once there is none left.
	local nextQuest = (not state.preview) and PrePick.NextDecideQuest(pending) or nil
	frame.Next.questID = nextQuest and nextQuest.questID or nil
	frame.Next:SetText(nextQuest and L["Next"] or L["Close"])
	frame.Next:ClearAllPoints()
	frame.Next:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
	frame.Next:Show()
	local foot = 10 + 22 + 4
	local needsPick = not state.preview and state.questID > 0 and decision ~= nil
		and not decision.pending and decision.action ~= "auto" and picked == nil
	frame.Hint:SetShown(needsPick)
	if needsPick then
		frame.Hint:ClearAllPoints()
		frame.Hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, foot)
		foot = foot + frame.Hint:GetStringHeight() + 6
	end
	frame.Reason:ClearAllPoints()
	frame.Reason:SetPoint("BOTTOM", frame, "BOTTOM", 0, foot)
	foot = foot + frame.Reason:GetStringHeight()
	local legendHeight = shown > 0 and (6 + frame.Legend:GetStringHeight()) or 0
	frame:SetHeight(-y + foot + legendHeight + 6 + 8)
	frame:Show()
end

-- The first quest after the shown one (list order) that still needs the player's
-- decision: not auto, no stored pick, item data loaded. nil when there is none.
function PrePick.NextDecideQuest(pending)
	local after = false
	for _, q in ipairs(pending or {}) do
		if after and not q.pending and not q.picked and q.action ~= "auto" then return q end
		if q.questID == state.questID then after = true end
	end
	return nil
end

-- The player clicked a reward: remember it (toggle off when clicked again).
function PrePick.Choose(c)
	if not c or not c.itemID or c.loaded ~= true or not state.questID or state.questID <= 0 then return end
	if state.preview then return end
	PrePick.InvalidatePending()
	if PrePick.Get(state.questID) == c.itemID then
		PrePick.Clear(state.questID)
		NS.Print(L["Pre-pick cleared for %s."], Data.QuestTitle(state.questID) or state.questID)
	else
		if not PrePick.Set(state.questID, c.itemID) then return end
		NS.Print(L["Pre-pick for %s: %s."], Data.QuestTitle(state.questID) or state.questID, Rewards.ChoiceLabel(c))
	end
	state.decision = Data.Evaluate(state.choices, NS.db.settings, Rules.Player(), state.questID)
	PrePick.Render()
end

--------------------------------------------------------------------------------
-- Preview (unlocked) mode: the settings checkbox "Unlock and show the pick window"
-- shows the window with sample rows so the player can drag it into place. The
-- rows are real items (by itemID) gathered and run through the engine exactly
-- like a quest's rewards, so the grid shows live deltas against the player's
-- gear. No quest is involved: clicks do nothing, the title says so, and hiding
-- it re-locks.
--------------------------------------------------------------------------------
-- Real sample items for preview: a sword, leather chest, and trinket.
PrePick.SAMPLE_ITEM_IDS = {
	5191,   -- Cruel Barb (one-hand sword, rare)
	10399,  -- Blackened Defias Armor (leather chest, rare)
	19024,  -- Arena Grand Master (trinket, Use effect)
}
PrePick.SAMPLE_QUEST_ID = -1

-- Gathers the sample items; retries while the client loads their data.
local function LoadSample(attempt, requestID)
	requestID = requestID or state.requestID
	attempt = attempt or 1
	if not state.preview or requestID ~= state.requestID then return end
	local source = Data.ItemListSource(PrePick.SAMPLE_ITEM_IDS)
	local choices = Rewards.Gather(source.Count(), source)
	local decision = Data.Evaluate(choices, NS.db.settings, Rules.Player())
	if decision.pending and attempt < PrePick.MAX_LOAD_TRIES then
		for _, c in ipairs(choices) do
			if c.loaded == false and c.itemID then NS.Call("C_Item.RequestLoadItemDataByID", c.itemID) end
		end
		NS.After(PrePick.RETRY_DELAY, function() LoadSample(attempt + 1, requestID) end)
	end
	state.choices, state.decision, state.source = choices, decision, source
	PrePick.Render()
end

function PrePick.SetUnlocked(unlocked)
	state.requestID = (state.requestID or 0) + 1
	if unlocked then
		if not frame then frame = BuildFrame() end
		state.questID, state.preview = PrePick.SAMPLE_QUEST_ID, true
		LoadSample()
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
function PrePick.Open(questID, force, attempt, requestID)
	if not requestID then
		state.requestID = (state.requestID or 0) + 1
		requestID = state.requestID
	end
	if requestID ~= state.requestID then return false end
	attempt = attempt or 1
	if not NS.db or not questID then return false end
	local source = Data.LogSource(questID)
	local n = NS.SafeNumber(source.Count()) or 0
	if n < 2 then
		if force then NS.Print(L["%s has no reward to choose."], Data.QuestTitle(questID) or questID) end
		return false
	end
	local choices = Rewards.Gather(n, source)
	local decision = Data.Evaluate(choices, NS.db.settings, Rules.Player(), questID)
	if decision.pending then
		if force then
			if not frame then frame = BuildFrame() end
			state.questID, state.choices, state.decision, state.preview = questID, choices, decision, false
			PrePick.Render()
		end
		if attempt >= PrePick.MAX_LOAD_TRIES then
			if force then NS.Print(L["the item data did not load in time"]) end
			return false
		end
		for _, c in ipairs(choices) do
			if c.loaded == false and c.itemID then NS.Call("C_Item.RequestLoadItemDataByID", c.itemID) end
		end
		NS.After(PrePick.RETRY_DELAY, function() PrePick.Open(questID, force, attempt + 1, requestID) end)
		return false
	end
	if not force and (decision.action == "auto" or not decision.index) then return false end
	if not frame then frame = BuildFrame() end
	state.preview = false
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
	NS.After(PrePick.OPEN_DELAY, function()
		PrePick.InvalidatePending()
		-- A newly accepted quest takes the window; when its reward is auto and the
		-- window already shows another quest, the quest list just gains a line.
		-- Preserve the user's current selection when several quests arrive together.
		if frame and frame:IsShown() then
			if not state.preview then PrePick.Render() end
			return
		end
		if not PrePick.Open(questID, false) and frame and frame:IsShown() and not state.preview then
			PrePick.Render()
		end
	end)
end)

-- Hand-in / abandon: drop the pre-pick; if the window showed that quest, move
-- on to the next pending one or close.
local function Forget(questID)
	questID = NS.SafeNumber(questID)
	if not questID then return end
	PrePick.InvalidatePending()
	if state.questID == questID and not state.preview then
		local wasShown = frame and frame:IsShown()
		PrePick.Hide()
		if wasShown then NS.After(PrePick.OPEN_DELAY, function() if not state.questID then PrePick.OpenAny() end end) end
	elseif frame and frame:IsShown() and not state.preview then
		PrePick.Render()
	end
end
NS.RegisterEvent("QUEST_TURNED_IN", Forget)
NS.RegisterEvent("QUEST_REMOVED", Forget)

-- /qam pick [questID]: open for the given quest, else the one selected in the log.
function PrePick.Command(rest)
	local questID = tonumber(rest)
	if not questID then
		questID = Data.SelectedQuestID()
	end
	if not questID or questID <= 0 then
		return PrePick.OpenAny()
	end
	PrePick.Open(questID, true)
end

function PrePick.DebugReport()
	NS.Print("Pre-picks: %d stored, window %s for %s", Model.GetSelectionCount(), frame and frame:IsShown() and "shown" or "hidden", tostring(state.questID))
end