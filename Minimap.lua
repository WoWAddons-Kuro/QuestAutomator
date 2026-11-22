-- Quest Automator: minimap button. Left-click toggles the pre-picker, right-click
-- opens settings; dragging changes its position. Automation is toggled in settings.
--
-- Placement: until the player drags the button, its angle is chosen automatically. The
-- buttons already sitting on the minimap ring (other addons' buttons are children of
-- Minimap, Blizzard's zoom / tracking / mail frames hang off Minimap and MinimapCluster)
-- are measured and the nearest free 30-degree slot to the preferred angle is taken, so
-- two addons that both default to the same spot no longer overlap. The preferred angle
-- is 190 (left, a slot below the usual 220) because Adventure Ledger sits at 220 and
-- Camp Tracker, avoiding it, lands at 250; the search still moves on if 190 is taken.
local ADDON, NS = ...
local L = NS.L

local ICON = "Interface\\Icons\\Achievement_Quests_Completed_08"
local RIM = 5               -- how far outside the minimap edge the button centre sits
NS.MINIMAP_PREFERRED_ANGLE = 190
local SLOT_STEP = 30        -- degrees between candidate spots
local MIN_SEPARATION = 24   -- two 31px buttons on a ~104px ring touch at about 17 degrees
local RING_TOLERANCE = 22   -- a frame this far from the ring radius counts as sitting on it
local button, icon

-- Forever uses the retail 198x198 minimap (Blizzard_Minimap\Mainline\Minimap.xml,
-- skinned by Blizzard_Minimap\Camelot\Skin.lua), so the orbit radius comes from the
-- live size: a fixed 80px (the classic minimap) would land inside the map.
local function Radius()
	local w, h = Minimap:GetWidth(), Minimap:GetHeight()
	local half = math.max(tonumber(w) or 0, tonumber(h) or 0) / 2
	if half < 40 then half = 99 end
	return half + RIM
end

local function Cfg()
	return NS.db.settings
end

local function UpdatePosition()
	if not button then return end
	local angle = math.rad(Cfg().minimapAngle or NS.MINIMAP_PREFERRED_ANGLE)
	local r = Radius()
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

-- Grey icon while the automation is off or paused for the session.
function NS.UpdateMinimapIcon()
	if not icon then return end
	local active = Cfg().enabled and not (NS.Auto and NS.Auto.SessionPaused())
	icon:SetDesaturated(not active)
	if active then
		icon:SetVertexColor(1, 1, 1)
	else
		icon:SetVertexColor(0.6, 0.6, 0.6)
	end
end

--------------------------------------------------------------------------------
-- Automatic placement.
--------------------------------------------------------------------------------
-- Angle (degrees) of a frame's centre around the minimap centre when the frame sits
-- on the ring; nil for frames elsewhere, hidden frames and our own button.
local function RingAngle(frame, mx, my, radius)
	if frame == button or type(frame) ~= "table" then return nil end
	local okShown, shown = pcall(frame.IsShown, frame)
	local zoom = Minimap and (frame == Minimap.ZoomIn or frame == Minimap.ZoomOut)
	if not zoom and (not okShown or not shown) then return nil end
	local ok, fx, fy = pcall(frame.GetCenter, frame)
	if not ok or type(fx) ~= "number" or type(fy) ~= "number" then return nil end
	local dx, dy = fx - mx, fy - my
	local dist = math.sqrt(dx * dx + dy * dy)
	if math.abs(dist - radius) > RING_TOLERANCE then return nil end
	return math.deg(math.atan2(dy, dx))
end

local function AddChildren(list, parent)
	if type(parent) ~= "table" or not parent.GetChildren then return end
	local ok, children = pcall(function() return { parent:GetChildren() } end)
	if not ok then return end
	for _, child in ipairs(children) do list[#list + 1] = child end
end

-- Angles of everything currently sitting on the ring.
function NS.OccupiedMinimapAngles()
	local angles = {}
	if not Minimap then return angles end
	local mx, my = Minimap:GetCenter()
	if type(mx) ~= "number" or type(my) ~= "number" then return angles end
	local radius = Radius()
	local frames = {}
	AddChildren(frames, Minimap)
	AddChildren(frames, MinimapBackdrop)
	AddChildren(frames, MinimapCluster)
	for _, frame in ipairs(frames) do
		local angle = RingAngle(frame, mx, my, radius)
		if angle then angles[#angles + 1] = angle end
	end
	return angles
end

local function AngleDistance(a, b)
	return math.abs((a - b + 180) % 360 - 180)
end

-- The candidate closest to `preferred` (preferred itself, then +30, -30, +60, -60, ...)
-- that keeps MIN_SEPARATION from every occupied angle. Falls back to `preferred`.
function NS.FreeMinimapAngle(preferred, occupied)
	preferred = preferred or NS.MINIMAP_PREFERRED_ANGLE
	for step = 0, math.floor(180 / SLOT_STEP) do
		for _, sign in ipairs({ 1, -1 }) do
			local candidate = (preferred + sign * step * SLOT_STEP) % 360
			local free = true
			for _, angle in ipairs(occupied) do
				if AngleDistance(candidate, angle) < MIN_SEPARATION then
					free = false
					break
				end
			end
			if free then return candidate end
			if step == 0 then break end
		end
	end
	return preferred % 360
end

-- Picks a free angle unless the player has dragged the button (or `force` is set).
function NS.PlaceMinimapButton(force)
	local settings = Cfg()
	if force then settings.minimapAngleAuto = true end
	if not settings.minimapAngleAuto or not button then return false end
	local occupied = NS.OccupiedMinimapAngles()
	local angle = NS.FreeMinimapAngle(NS.MINIMAP_PREFERRED_ANGLE, occupied)
	if angle ~= settings.minimapAngle then
		settings.minimapAngle = angle
		UpdatePosition()
		return true
	end
	return false
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	if not (mx and cx and scale and scale > 0) then return end
	cx, cy = cx / scale, cy / scale
	Cfg().minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
	Cfg().minimapAngleAuto = false
	UpdatePosition()
end

local function ShowTooltip(owner)
	if not GameTooltip then return end
	local s = Cfg()
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine(L["Quest Automator"])
	local paused = NS.Auto and NS.Auto.SessionPaused()
	GameTooltip:AddLine(string.format(L["Automation: %s%s"], s.enabled and L["on"] or L["off"],
		paused and (" (" .. L["paused for this session"] .. ")") or ""), 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Reward choice"], NS.RewardModeName(s.rewardMode), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Pause key"], L["Shift / Ctrl / Alt"], 1, 1, 1, 1, 1, 1)
	local quests = NS.PrePick and NS.PrePick.PendingQuests() or {}
	if #quests > 0 then
		GameTooltip:AddLine(string.format(L["Rewards to choose: %d"], #quests), 1, 0.82, 0)
		for _, quest in ipairs(quests) do
			local status = NS.PrePick.StatusText(quest)
			GameTooltip:AddDoubleLine(quest.title or ("#" .. quest.questID), status, 1, 1, 1, 1, 0.82, 0)
		end
	end
	GameTooltip:AddLine(L["Pre-select your reward."], 1, 0.65, 0.2, true)
	GameTooltip:AddLine(L["Left-click: toggle the pick window. Right-click: settings. Drag to move."], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Right-click menu (Blizzard_Menu's MenuUtil, the 11.x context menu API; falls
-- back to opening the settings page when it is missing).
--------------------------------------------------------------------------------
local function Flag(root, key, label)
	root:CreateCheckbox(label,
		function() return Cfg()[key] and true or false end,
		function() NS.SetFlag(key, "", label) end)
end

local function Generator(owner, root)
	root:CreateTitle(L["Quest Automator"])
	Flag(root, "enabled", L["Enable the automation"])
	Flag(root, "accept", L["Accept quests"])
	Flag(root, "turnIn", L["Hand in quests"])
	root:CreateDivider()
	for _, mode in ipairs(NS.REWARD_MODES) do
		root:CreateRadio(L["Reward: %s"]:format(NS.RewardModeName(mode)),
			function() return Cfg().rewardMode == mode end,
			function()
				Cfg().rewardMode = mode
				NS.Print("%s: %s", L["Reward choice"], NS.RewardModeName(mode))
				NS.OnSettingsChanged()
			end)
	end
	Flag(root, "announce", L["Announcements"])
	Flag(root, "xpBar", L["Completed quests on the experience bar"])
	root:CreateDivider()
	local paused = NS.Auto and NS.Auto.SessionPaused()
	root:CreateButton(paused and L["Resume the automation"] or L["Pause for this session"],
		function() NS.Auto.SetSessionPaused(not NS.Auto.SessionPaused()) end)
	root:CreateButton(L["Settings"], function() NS.OpenSettings() end)
	root:CreateButton(L["Status"], function() NS.PrintStatus() end)
	root:CreateDivider()
	root:CreateButton(L["Move the minimap button to a free spot"], function() NS.PlaceMinimapButton(true) end)
	root:CreateButton(L["Hide minimap button"], function() NS.ToggleMinimap() end)
end

function NS.OpenMinimapMenu(owner)
	if MenuUtil and MenuUtil.CreateContextMenu then
		local ok, err = pcall(MenuUtil.CreateContextMenu, owner, Generator)
		if ok then return true end
		NS.WarnOnce("menu", err)
	end
	NS.features["MenuUtil.CreateContextMenu"] = false
	return NS.OpenSettings()
end

--------------------------------------------------------------------------------
-- Button.
--------------------------------------------------------------------------------
local function CreateButton()
	button = CreateFrame("Button", "QuestAutomatorMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetMovable(true)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
	icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
	button.icon = icon

	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			NS.OpenSettings()
		else
			if NS.PrePick then NS.PrePick.Toggle() end
		end
	end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	button:SetScript("OnShow", UpdatePosition)
	UpdatePosition()
	NS.UpdateMinimapIcon()
	NS.PlaceMinimapButton(false)
end

function NS.ShowMinimapButton(show)
	if not Minimap then
		NS.features["Minimap"] = false
		return
	end
	NS.features["Minimap"] = true
	if show then
		if not button then CreateButton() end
		button:Show()
		UpdatePosition()
		NS.UpdateMinimapIcon()
	elseif button then
		button:Hide()
	end
end

function NS.ToggleMinimap()
	local settings = Cfg()
	settings.minimap = not settings.minimap
	NS.ShowMinimapButton(settings.minimap)
	NS.Print(settings.minimap and L["Minimap button shown."] or L["Minimap button hidden (/qam minimap brings it back)."])
end

NS.RegisterEvent("PLAYER_LOGIN", function()
	if NS.db and NS.db.settings.minimap then
		NS.ShowMinimapButton(true)
		-- Other addons may create their buttons after ours: look again once they have.
		NS.After(1, function() NS.PlaceMinimapButton(false) end)
	end
end)

NS.RegisterEvent("PLAYER_ENTERING_WORLD", function()
	NS.After(2, function() NS.PlaceMinimapButton(false) end)
end)
