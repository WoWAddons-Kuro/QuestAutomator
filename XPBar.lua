-- Quest Automator: the experience the completed quests in the log are worth,
-- drawn onto Blizzard's experience bar the way the bar draws rested experience.
-- A gold fill runs from the current experience to where the bar will stand once
-- every completed quest is handed in, ended by a gold pip. When the hand-ins cross
-- one or more levels a light shade covers the rest of the current level and the gold
-- fill shows the bar of the level they reach (60% + 60% of a level = light from 60% to
-- the end, gold to 20% marked "+1"); at the level cap the light shade runs to the end
-- and the pip sits at the right edge marked "Max". Hovering the bar adds the totals to its tooltip.
--
-- Where the bar lives (Blizzard_StatusTrackingBar, build 69893, loaded on camelot):
-- StatusTrackingBarManager.barContainers (Main / Secondary) each create their own
-- bar per kind in InitializeBars; the experience bar is
-- container.bars[StatusTrackingBarInfo.BarsEnum.Experience] (ExpStatusBarTemplate),
-- its fill is the child StatusBar. Nothing is written into Blizzard's frames: the
-- overlay is our own child frame, the bar's Update method and scripts are post-hooked.
--
-- Quest experience: GetQuestLogRewardXP(questID) (undocumented global; returns
-- totalXp, baseXp in Mainline\QuestUtils.lua:771). Levels past the current one come
-- from the vanilla experience table, which matches Forever where checked (400 at
-- level 1, 36,400 at level 26); a level's UnitXPMax that differs is remembered.
local ADDON, NS = ...
local L = NS.L
local format = string.format

local XPBar = {}
NS.XPBar = XPBar

XPBar.COLOR = { 1, 0.78, 0.15 } -- quest gold
XPBar.FILL_ALPHA = 0.6
-- The shade over the rest of a level the hand-ins finish: the same tinted gold atlas as
-- the fill (in the client, 2026-11-07: a pale tint of the atlas at 0.35 all but vanished on
-- the dark bar, and a plain pale-gold colour at 0.45 looked too dark; the player preferred
-- the fill's gold).
XPBar.COVER_COLOR = XPBar.COLOR
XPBar.COVER_ALPHA = XPBar.FILL_ALPHA
XPBar.FILL_ATLAS = "UI-HUD-ExperienceBar-Fill-Experience"
XPBar.PIP_ATLAS = "UI-HUD-ExperienceBar-Frame-Pip"

-- Experience needed to go from level n to n + 1 (vanilla; Forever checked at 1 and 26).
XPBar.XP_TO_LEVEL = {
	400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
	8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
	25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
	50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
	95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
	153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

local overlays = {} -- experience bar -> overlay frame
XPBar.overlays = overlays
local state = { pending = false, summary = nil }
XPBar.state = state

--------------------------------------------------------------------------------
-- Data.
--------------------------------------------------------------------------------
local function LearnedTable()
	local db = NS.db
	if not db then return nil end
	if type(db.xpMax) ~= "table" then db.xpMax = {} end
	return db.xpMax
end

-- Experience needed to leave `level`; `fallback` when neither the client nor the table knows.
function XPBar.XPForLevel(level, fallback)
	local learned = LearnedTable()
	return (learned and learned[level]) or XPBar.XP_TO_LEVEL[level] or fallback
end

-- Remembers the current level's requirement when it differs from the table.
local function Learn(level, max)
	local learned = LearnedTable()
	if not learned or not level or not max or max <= 0 then return end
	if XPBar.XP_TO_LEVEL[level] == max then
		learned[level] = nil
	else
		learned[level] = max
	end
end

function XPBar.MaxLevel()
	local util = GameRulesUtil
	if type(util) == "table" and type(util.GetEffectiveMaxLevelForPlayer) == "function" then
		local ok, level = pcall(util.GetEffectiveMaxLevelForPlayer)
		level = ok and NS.SafeNumber(level) or nil
		if level and level > 0 then return level end
	end
	return NS.SafeNumber(NS.Call("GetMaxPlayerLevel")) or (#XPBar.XP_TO_LEVEL + 1)
end

-- The quest log's own rules (Mainline\QuestMapFrame.lua, loaded on camelot): an entry is
-- listed when it is not a task and not hidden (:1663), and it reads as complete when
-- C_QuestLog.IsComplete is true (:1888). ReadyForTurnIn is not what the log shows, and
-- the hidden entries (tracking quests) never appear in it, so neither is counted.
local function ListedInLog(info)
	return not NS.SafeBool(info.isHeader) and not NS.SafeBool(info.isHidden) and not NS.SafeBool(info.isTask)
end

local function QuestComplete(questID)
	if NS.SafeBool(NS.Call("C_QuestLog.IsFailed", questID)) then return false end
	return NS.SafeBool(NS.Call("C_QuestLog.IsComplete", questID))
end

-- Completed quests in the log and the experience they give: total, list of { questID, title, xp }.
function XPBar.CompletedQuests()
	local total, list = 0, {}
	local entries = NS.SafeNumber(NS.Call("C_QuestLog.GetNumQuestLogEntries")) or 0
	for index = 1, entries do
		local info = NS.Call("C_QuestLog.GetInfo", index)
		if type(info) == "table" and ListedInLog(info) then
			local questID = NS.SafeNumber(info.questID)
			if questID and questID > 0 and QuestComplete(questID) then
				local xp = NS.SafeNumber(NS.Call("GetQuestLogRewardXP", questID)) or 0
				if xp > 0 then
					total = total + xp
					list[#list + 1] = { questID = questID, title = NS.SafeString(info.title), xp = xp }
				end
			end
		end
	end
	return total, list
end

-- Where `gain` experience takes a character at `level` with `cur` of `max`:
-- { level, cur, max, levels = levels gained, capped = reached maxLevel }.
function XPBar.Project(level, cur, max, gain, maxLevel)
	local levels = 0
	while gain > 0 and level < maxLevel do
		local need = max - cur
		if gain < need then
			cur, gain = cur + gain, 0
		else
			gain = gain - need
			level, levels, cur = level + 1, levels + 1, 0
			if level < maxLevel then
				max = XPBar.XPForLevel(level, max)
			end
		end
	end
	return { level = level, cur = cur, max = max, levels = levels, capped = level >= maxLevel }
end

-- Everything the overlay and tooltip draw, or nil when there is nothing to show.
function XPBar.Summary()
	local level = NS.SafeNumber(UnitLevel and UnitLevel("player"))
	local cur = NS.SafeNumber(NS.Call("UnitXP", "player"))
	local max = NS.SafeNumber(NS.Call("UnitXPMax", "player"))
	if not level or not cur or not max or max <= 0 then return nil end
	local maxLevel = XPBar.MaxLevel()
	if level >= maxLevel or NS.SafeBool(NS.Call("IsXPUserDisabled")) then return nil end
	Learn(level, max)
	local total, list = XPBar.CompletedQuests()
	if total <= 0 then return nil end
	return {
		level = level, cur = cur, max = max, xp = total, quests = list,
		after = XPBar.Project(level, cur, max, total, maxLevel),
	}
end

-- Bar fractions for a summary:
--   from, to   the gold fill (inside the level: current -> after; past it: the level reached)
--   pip        where the marker stands; label: "+N" levels or "Max", nil inside the level
--   coverFrom, coverTo  the light shade over the rest of the current level when the hand-ins
--              finish it, so the player sees that all of it is covered (nil otherwise)
function XPBar.Layout(summary)
	local after = summary.after
	local now = summary.cur / summary.max
	if after.levels == 0 then
		local to = after.cur / after.max
		return { from = now, to = to, pip = to }
	end
	if after.capped then
		return { from = 1, to = 1, pip = 1, label = L["Max"], coverFrom = now, coverTo = 1 }
	end
	local to = after.cur / after.max
	return { from = 0, to = to, pip = to, label = "+" .. after.levels, coverFrom = now, coverTo = 1 }
end

--------------------------------------------------------------------------------
-- The overlay.
--------------------------------------------------------------------------------
local function TintedAtlas(texture, atlas, r, g, b, a)
	local ok, found = pcall(texture.SetAtlas, texture, atlas)
	if ok and found ~= false then
		texture:SetDesaturated(true)
		texture:SetVertexColor(r, g, b, a)
		return true
	end
	texture:SetColorTexture(r, g, b, a)
	return false
end

local function BuildOverlay(bar)
	local status = bar.StatusBar or bar
	local o = CreateFrame("Frame", nil, bar)
	o.status = status
	o:SetAllPoints(status)
	o:SetFrameLevel((status:GetFrameLevel() or 1) + 2)
	o:EnableMouse(false)
	local r, g, b = unpack(XPBar.COLOR)

	local cr, cg, cb = unpack(XPBar.COVER_COLOR)
	o.Cover = o:CreateTexture(nil, "ARTWORK", nil, -1)
	o.atlasCover = TintedAtlas(o.Cover, XPBar.FILL_ATLAS, cr, cg, cb, XPBar.COVER_ALPHA)

	o.Fill = o:CreateTexture(nil, "ARTWORK", nil, 0)
	o.atlasFill = TintedAtlas(o.Fill, XPBar.FILL_ATLAS, r, g, b, XPBar.FILL_ALPHA)

	o.Pip = o:CreateTexture(nil, "OVERLAY")
	o.atlasPip = TintedAtlas(o.Pip, XPBar.PIP_ATLAS, r, g, b, 1)
	if o.atlasPip then
		o.Pip:SetSize(10, 14)
	else
		o.Pip:SetSize(2, 14)
	end

	o.Label = o:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	o.Label:SetTextColor(r, g, b)
	o.Label:SetPoint("BOTTOM", o.Pip, "TOP", 0, 0)

	o:Hide()
	overlays[bar] = o
	return o
end

local function Clamp01(x)
	return math.max(0, math.min(1, x))
end

-- Lays `texture` over the bar from fraction `from` to `to`; hidden when the span is empty.
-- Returns the clamped span, or nil when nothing is drawn.
local function Span(o, texture, isAtlas, from, to, width)
	texture:ClearAllPoints()
	if not from or not to then
		texture:Hide()
		return nil
	end
	from = Clamp01(from)
	to = math.max(from, Clamp01(to))
	local w = (to - from) * width
	if w < 0.5 then
		texture:Hide()
		return nil
	end
	texture:SetPoint("TOPLEFT", o, "TOPLEFT", from * width, 0)
	texture:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", from * width, 0)
	texture:SetWidth(w)
	if isAtlas then texture:SetTexCoord(from, to, 0, 1) end
	texture:Show()
	return from, to
end

local function Draw(o, summary)
	if not summary then
		o:Hide()
		return
	end
	local width = NS.SafeNumber(o.status:GetWidth()) or 0
	if width <= 0 then
		o:Hide()
		return
	end
	local layout = XPBar.Layout(summary)
	local label = layout.label
	o.from, o.to = Span(o, o.Fill, o.atlasFill, layout.from, layout.to, width)
	o.coverFrom, o.coverTo = Span(o, o.Cover, o.atlasCover, layout.coverFrom, layout.coverTo, width)
	o.label = label
	local pip = Clamp01(layout.pip)
	o.pip = pip

	o.Pip:ClearAllPoints()
	o.Pip:SetPoint("CENTER", o, "LEFT", pip * width, 0)
	o.Pip:Show()
	o.Label:SetText(label or "")
	o.Label:SetShown(label ~= nil)
	o:Show()
end

--------------------------------------------------------------------------------
-- Finding Blizzard's experience bars and keeping the overlay current.
--------------------------------------------------------------------------------
local function ExperienceIndex()
	local info = StatusTrackingBarInfo
	return type(info) == "table" and type(info.BarsEnum) == "table" and info.BarsEnum.Experience or nil
end

local AddTooltip

local function Attach(bar)
	if overlays[bar] then return overlays[bar] end
	local o = BuildOverlay(bar)
	if type(bar.Update) == "function" then
		hooksecurefunc(bar, "Update", function() XPBar.RequestRefresh() end)
	end
	if bar.HookScript then
		bar:HookScript("OnShow", function() XPBar.RequestRefresh() end)
		bar:HookScript("OnSizeChanged", function() XPBar.RequestRefresh() end)
		bar:HookScript("OnEnter", function(self) AddTooltip(self) end)
	end
	return o
end

-- Every experience bar Blizzard made (one per bar container); attaches overlays to new ones.
function XPBar.Bars()
	local found = {}
	local index = ExperienceIndex()
	local manager = StatusTrackingBarManager
	if not index or type(manager) ~= "table" then return found end
	local containers = manager.barContainers
	if type(containers) ~= "table" then
		containers = { manager.MainStatusTrackingBarContainer, manager.SecondaryStatusTrackingBarContainer }
	end
	for _, container in pairs(containers) do
		local bar = type(container) == "table" and type(container.bars) == "table" and container.bars[index]
		if type(bar) == "table" then
			found[#found + 1] = bar
			Attach(bar)
		end
	end
	return found
end

-- The minimap menu's switch (settings.xpBar); on unless switched off.
function XPBar.Enabled()
	return not (NS.db and NS.db.settings and NS.db.settings.xpBar == false)
end

function XPBar.Refresh()
	state.pending = false
	local bars = XPBar.Bars()
	local summary = XPBar.Enabled() and XPBar.Summary() or nil
	state.summary = summary
	for _, bar in ipairs(bars) do
		Draw(overlays[bar], summary)
	end
end

-- Quest log events come in bursts; draw once on the next frame.
function XPBar.RequestRefresh()
	if state.pending then return end
	state.pending = true
	NS.After(0, XPBar.Refresh)
end

local function Number(n)
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
	return tostring(n)
end

function XPBar.AfterText(summary)
	local after = summary.after
	if after.capped then
		return format(L["After handing them in: level %d (maximum)"], after.level)
	end
	return format(L["After handing them in: level %d, %d%%"], after.level, math.floor(after.cur / after.max * 100))
end

function AddTooltip(bar)
	local summary = state.summary
	if not summary or not GameTooltip then return end
	if not GameTooltip:IsShown() then
		GameTooltip:SetOwner(bar, "ANCHOR_TOP")
	else
		GameTooltip:AddLine(" ")
	end
	local r, g, b = unpack(XPBar.COLOR)
	GameTooltip:AddLine(format(L["Completed quests: %d (+%s experience)"], #summary.quests, Number(summary.xp)), r, g, b)
	GameTooltip:AddLine(XPBar.AfterText(summary), 1, 1, 1)
	GameTooltip:Show()
end

function XPBar.DebugReport()
	local bars = XPBar.Bars()
	if not XPBar.Enabled() then
		NS.Print("Experience bar: %d bar(s) found, overlay switched off (minimap menu).", #bars)
		return
	end
	local summary = XPBar.Summary()
	if not summary then
		NS.Print("Experience bar: %d bar(s) found, no completed quest experience to show.", #bars)
		return
	end
	NS.Print("Experience bar: %d bar(s) found, %d completed quest(s) worth %d XP; level %d %d/%d -> level %d %d/%d (+%d)%s",
		#bars, #summary.quests, summary.xp, summary.level, summary.cur, summary.max,
		summary.after.level, summary.after.cur, summary.after.max, summary.after.levels,
		summary.after.capped and " capped" or "")
	local layout = XPBar.Layout(summary)
	local function Pct(x) return x and math.floor(x * 100 + 0.5) or nil end
	NS.Print("  drawn: gold %s%%-%s%%, light shade %s, pip %d%%%s", tostring(Pct(layout.from)), tostring(Pct(layout.to)),
		layout.coverFrom and format("%d%%-%d%%", Pct(layout.coverFrom), Pct(layout.coverTo)) or "none",
		Pct(layout.pip), layout.label and (" " .. layout.label) or "")
	for _, q in ipairs(summary.quests) do
		NS.Print("  %d %s: %d XP", q.questID, tostring(q.title), q.xp)
	end
end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
	"QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN" }) do
	NS.RegisterEvent(event, XPBar.RequestRefresh)
end
