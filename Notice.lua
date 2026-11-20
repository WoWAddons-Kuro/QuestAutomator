-- Quest Automator: a one-line notice on the gossip or greeting panel when the
-- automation leaves it open on purpose (every quest offered is grey, repeatable
-- or ignored). Without it the player sees a panel that simply did not close and
-- cannot tell whether the addon is broken or declined on purpose.
--
-- The line is our own frame parented to Blizzard's panel (GossipFrame or
-- QuestFrame), placed to the left of the Goodbye button, so it hides with the
-- panel. Nothing in Blizzard's tables is written.
local ADDON, NS = ...
local L = NS.L
local Notice = {}
NS.Notice = Notice

-- stage -> panel the notice belongs to, and the Goodbye button it sits beside
-- (Forever's GossipFrame.GreetingPanel.GoodbyeButton, Era's global buttons).
Notice.PANELS = { gossip = "GossipFrame", greeting = "QuestFrame" }
Notice.GOODBYE_BUTTONS = {
	gossip = { "GossipFrame.GreetingPanel.GoodbyeButton", "GossipFrameGreetingGoodbyeButton" },
	greeting = { "QuestFrameGreetingGoodbyeButton", "QuestFrame.GreetingPanel.GoodbyeButton" },
}
Notice.COLOR = { 1, 0.82, 0 } -- Blizzard's NORMAL_FONT_COLOR (gold)

local frames = {} -- stage -> notice frame
Notice.frames = frames

local function Resolve(path)
	local cur = _G
	for part in string.gmatch(path, "[^%.]+") do
		if type(cur) ~= "table" then return nil end
		cur = cur[part]
		if cur == nil then return nil end
	end
	return cur
end

local function FindGoodbye(stage)
	for _, path in ipairs(Notice.GOODBYE_BUTTONS[stage] or {}) do
		local button = Resolve(path)
		if type(button) == "table" and type(button.GetObjectType) == "function" then return button end
	end
	return nil
end

local function Build(stage)
	local parent = _G[Notice.PANELS[stage] or ""]
	if type(parent) ~= "table" or type(parent.CreateFontString) ~= "function" then return nil end
	local frame = CreateFrame("Frame", nil, parent)
	local okLevel, level = pcall(parent.GetFrameLevel, parent)
	if okLevel and type(level) == "number" then pcall(frame.SetFrameLevel, frame, level + 10) end
	local goodbye = FindGoodbye(stage)
	if goodbye then
		frame:SetPoint("TOP", goodbye, "TOP", 0, 0)
		frame:SetPoint("BOTTOM", goodbye, "BOTTOM", 0, 0)
		frame:SetPoint("RIGHT", goodbye, "LEFT", -8, 0)
		frame:SetPoint("LEFT", parent, "LEFT", 24, 0)
	else
		frame:SetHeight(20)
		frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 24, 14)
		frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, 14)
	end
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetAllPoints(frame)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("MIDDLE")
	if text.SetWordWrap then text:SetWordWrap(false) end
	text:SetTextColor(Notice.COLOR[1], Notice.COLOR[2], Notice.COLOR[3])
	frame.text = text
	frame.anchoredToGoodbye = goodbye ~= nil
	frame:Hide()
	return frame
end

-- Shows `message` on the panel of `stage` ("gossip" | "greeting"). False when the
-- panel does not exist on this client.
function Notice.Show(stage, message)
	local frame = frames[stage]
	if not frame then
		local ok, built = pcall(Build, stage)
		if not ok then
			NS.WarnOnce("notice:" .. tostring(stage), tostring(built))
			return false
		end
		if not built then return false end
		frame = built
		frames[stage] = frame
	end
	frame.text:SetText(tostring(message or ""))
	frame:Show()
	return true
end

function Notice.Hide(stage)
	local frame = frames[stage]
	if frame then frame:Hide() end
end

function Notice.HideAll()
	for _, frame in pairs(frames) do frame:Hide() end
end

-- The notice is about a panel that is on screen; any later stage or a close
-- makes it stale.
for _, event in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
	NS.RegisterEvent(event, Notice.HideAll)
end

function Notice.DebugReport()
	local shown = {}
	for stage, frame in pairs(frames) do
		if frame:IsShown() then shown[#shown + 1] = stage end
	end
	NS.Print("Notice: frames %d, shown %s", #NS.SortedKeys(frames), #shown > 0 and table.concat(shown, ",") or "none")
end
