-- Quest Automator: core namespace, feature detection, saved variables,
-- event plumbing, the log ring buffer and the slash commands.
local ADDON, NS = ...
QuestAutomator = NS -- global handle so /dump QuestAutomator.db works in-game

local L = NS.L
local format = string.format

NS.name = ADDON
NS.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local PREFIX = "|cff4fc3f7" .. L["Quest Automator"] .. ":|r "

function NS.Print(msg, ...)
	if select("#", ...) > 0 then
		msg = format(tostring(msg), ...)
	end
	local frame = DEFAULT_CHAT_FRAME or ChatFrame1
	if frame and frame.AddMessage then
		frame:AddMessage(PREFIX .. tostring(msg))
	end
end

NS.warned = {}
function NS.WarnOnce(key, msg)
	if NS.warned[key] then return end
	NS.warned[key] = msg or true
	NS.Print(L["Warning: %s"], tostring(msg or key))
end

--------------------------------------------------------------------------------
-- Feature detection. Every API whose presence on Forever is not certain goes
-- through NS.Feature so `/qam debug` can list what is active.
--------------------------------------------------------------------------------
NS.features = {}

local function Resolve(path)
	local cur = _G
	for part in string.gmatch(path, "[^%.]+") do
		if type(cur) ~= "table" then return nil end
		cur = cur[part]
		if cur == nil then return nil end
	end
	return cur
end

function NS.Feature(path)
	local value = Resolve(path)
	NS.features[path] = (value ~= nil)
	return value
end

local function Pack(...)
	return { n = select("#", ...), ... }
end

-- Calls a global or C_* function by name if it exists, returning every value it
-- returns (C_Item.GetItemInfo has 18); nil when it is missing or throws.
function NS.Call(path, ...)
	local fn = Resolve(path)
	if type(fn) ~= "function" then
		NS.features[path] = false
		return nil
	end
	NS.features[path] = true
	local results = Pack(pcall(fn, ...))
	if not results[1] then
		NS.WarnOnce("call:" .. path, path .. " -> " .. tostring(results[2]))
		return nil
	end
	return unpack(results, 2, results.n)
end

--------------------------------------------------------------------------------
-- Secret values (retail 12.x). Quest and gossip data carry no secret flags in
-- this build's documentation, but every value read from the client still goes
-- through NS.Safe so an unexpected secret becomes nil instead of an error.
--------------------------------------------------------------------------------
local issecretvalue = NS.Feature("issecretvalue")
local canaccessvalue = NS.Feature("canaccessvalue")

function NS.Safe(value)
	if value == nil then return nil end
	if canaccessvalue then
		if not canaccessvalue(value) then return nil end
	elseif issecretvalue then
		if issecretvalue(value) then return nil end
	end
	return value
end

function NS.SafeNumber(value)
	local v = NS.Safe(value)
	if type(v) == "number" then return v end
	return nil
end

function NS.SafeString(value)
	local v = NS.Safe(value)
	if type(v) == "string" then return v end
	return nil
end

function NS.SafeBool(value)
	local v = NS.Safe(value)
	if v == true or v == 1 then return true end
	return false
end

--------------------------------------------------------------------------------
-- Event plumbing. Registration is wrapped in pcall so an event that does not
-- exist on this client is recorded as unavailable instead of throwing. Handlers
-- run inside pcall; the first error per event is shown once and kept for debug.
--------------------------------------------------------------------------------
NS.handlers = {}
NS.eventStatus = {}
NS.eventErrors = {}

local eventFrame = CreateFrame("Frame")
NS.eventFrame = eventFrame

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = NS.handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then
			NS.eventErrors[event] = tostring(err)
			NS.WarnOnce("event:" .. event, event .. " -> " .. tostring(err))
		end
	end
end)

function NS.RegisterEvent(event, handler)
	if NS.handlers[event] then
		table.insert(NS.handlers[event], handler)
		return true
	end
	local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
	if ok then
		NS.handlers[event] = { handler }
		NS.eventStatus[event] = "active"
	else
		NS.eventStatus[event] = "unavailable: " .. tostring(err)
	end
	return ok
end

function NS.After(seconds, fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(seconds, fn)
	else
		fn()
	end
end

function NS.Now()
	if GetTime then return GetTime() end
	return os.time()
end

--------------------------------------------------------------------------------
-- Saved variables.
--   QuestAutomatorDB (account): settings, ignored NPCs and quests, log.
--   QuestAutomatorCharDB (character): stat override, counters.
-- Build 69913 writes both files at logout but does not always load them at the
-- next start (a client bug, see README); nothing here can work around that.
--------------------------------------------------------------------------------
NS.SETTINGS_VERSION = 1
NS.DEFAULT_SETTINGS = {
	enabled = true,            -- master switch
	accept = true,             -- accept quests offered by NPCs
	turnIn = true,             -- hand in completed quests
	acceptTrivial = false,     -- also accept low-level (grey) quests
	acceptRepeatable = false,  -- also accept daily / repeatable quests
	turnInRepeatable = false,  -- also hand in daily / repeatable quests (they usually consume items)
	confirmPartyQuests = true, -- accept escort quests started by a party member
	rewardMode = "fit",        -- "fit" (armour type + stats), "value" (most expensive), "manual"
	weapons = false,           -- let the addon pick weapons too; off, any weapon among the choices leaves the whole choice to you
	trinkets = false,          -- let the addon pick trinkets too; same rule
	fallbackToValue = true,    -- fit mode: nothing usable -> take the most valuable reward
	manualQuality = 3,         -- a reward of this quality or better is left to the player (-1 = never); 3 = Rare
	announce = true,           -- chat line for every quest accepted, handed in and reward chosen
	minimap = true,            -- minimap button
	xpBar = true,              -- completed quests' experience on the experience bar (XPBar.lua)
	tooltipScore = true,       -- the reward scorer's verdict on every equipment tooltip (Tooltip.lua)
	ahScore = true,            -- "+1.2" upgrade bubble on equipment rows of the auction house browse list (AuctionScore/)
	minimapAngle = 190,        -- where the minimap button sits, in degrees
	minimapAngleAuto = true,   -- pick a free spot on the ring until the player drags the button
	settingsVersion = NS.SETTINGS_VERSION,
}

-- Called after any setting changes (slash command, settings page, menu) so the
-- minimap icon and anything else that mirrors the settings can follow.
function NS.OnSettingsChanged()
	if NS.UpdateMinimapIcon then NS.UpdateMinimapIcon() end
	if NS.Glow and NS.Glow.OnSettingsChanged then NS.Glow.OnSettingsChanged() end
	if NS.XPBar and NS.XPBar.Refresh then NS.XPBar.Refresh() end
end

NS.REWARD_MODES = { "fit", "value", "manual" }
NS.QUALITY_CHOICES = { -1, 1, 2, 3, 4, 5 } -- never, Common, Uncommon, Rare, Epic, Legendary (Enum.ItemQuality)

-- Quality name coloured like the client does (ITEM_QUALITY<n>_DESC, ITEM_QUALITY_COLORS).
function NS.QualityName(quality)
	quality = tonumber(quality)
	if not quality or quality < 0 then return L["never"] end
	local name = _G["ITEM_QUALITY" .. quality .. "_DESC"]
	if type(name) ~= "string" then name = L["quality %d"]:format(quality) end
	local colors = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local hex = colors and colors.hex
	if type(hex) == "string" then return hex .. name .. "|r" end
	return name
end

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = CopyDefaults({}, v)
			else
				dst[k] = v
			end
		end
	end
	return dst
end

local function LoadedTable(sv)
	if type(sv) == "table" then return sv end
	return nil
end

local function Contains(list, value)
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

function NS.CharKey()
	local name = UnitName and UnitName("player") or nil
	if type(name) ~= "string" or name == "" then return nil end
	local realm = GetRealmName and GetRealmName() or nil
	return name .. "-" .. tostring(realm or "")
end

function NS.InitDB()
	local db = LoadedTable(QuestAutomatorDB) or {}
	NS.svSource = LoadedTable(QuestAutomatorDB) and "account" or "fresh"
	QuestAutomatorDB = db
	db.version = 1
	local settings = CopyDefaults(type(db.settings) == "table" and db.settings or {}, NS.DEFAULT_SETTINGS)
	settings.settingsVersion = NS.SETTINGS_VERSION
	if not Contains(NS.REWARD_MODES, settings.rewardMode) then settings.rewardMode = NS.DEFAULT_SETTINGS.rewardMode end
	settings.weaponOffered, settings.trinketOffered = nil, nil -- removed in 0.2.0: a weapon or trinket offered always leaves the choice to the player
	settings.modifier = nil -- removed: any modifier key (Shift, Ctrl or Alt) always pauses the conversation
	if not Contains(NS.QUALITY_CHOICES, settings.manualQuality) then settings.manualQuality = NS.DEFAULT_SETTINGS.manualQuality end
	db.settings = settings
	db.ignoredNPCs = type(db.ignoredNPCs) == "table" and db.ignoredNPCs or {}     -- npcID -> name
	db.ignoredQuests = type(db.ignoredQuests) == "table" and db.ignoredQuests or {} -- questID -> title
	db.log = type(db.log) == "table" and db.log or {}
	NS.db = db

	local cdb = LoadedTable(QuestAutomatorCharDB) or {}
	NS.charSource = LoadedTable(QuestAutomatorCharDB) and "character" or "fresh"
	QuestAutomatorCharDB = cdb
	cdb.version = 1
	cdb.stats = type(cdb.stats) == "table" and cdb.stats or nil -- list of stat keys overriding the class profile
	cdb.counts = CopyDefaults(type(cdb.counts) == "table" and cdb.counts or {}, { accepted = 0, turnedIn = 0, chosen = 0, left = 0 })
	NS.chardb = cdb
	NS.loaded = true
end

--------------------------------------------------------------------------------
-- Log: a ring buffer in the account file so a session can be reviewed
-- afterwards (`/qam log`). Entries: { t = epoch, kind, msg }.
--------------------------------------------------------------------------------
NS.LOG_CAP = 150

function NS.Log(kind, msg, ...)
	local log = NS.db and NS.db.log
	if not log then return end
	if select("#", ...) > 0 then msg = format(tostring(msg), ...) end
	log[#log + 1] = { t = time(), kind = kind, msg = msg }
	while #log > NS.LOG_CAP do
		table.remove(log, 1)
	end
end

function NS.Announce(msg, ...)
	if select("#", ...) > 0 then msg = format(tostring(msg), ...) end
	NS.Log("info", msg)
	if NS.db and NS.db.settings.announce then
		NS.Print(msg)
	end
end

--------------------------------------------------------------------------------
-- Formatting helpers.
--------------------------------------------------------------------------------
-- Coin icons from the client's money frame atlas (the same texture the tooltip's
-- "Sell Price" line uses). 0:0 sizes the icon to the font height.
NS.COIN_ICONS = {
	gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}

-- "12 [g] 34 [s] 56 [c]" with coin icons; plain letters when plain = true (logs).
function NS.FormatMoney(copper, plain)
	copper = math.floor((tonumber(copper) or 0) + 0.5)
	if copper < 0 then copper = 0 end
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if plain then
		if gold > 0 then return format(L["%dg %ds %dc"], gold, silver, c) end
		if silver > 0 then return format(L["%ds %dc"], silver, c) end
		return format(L["%dc"], c)
	end
	local I = NS.COIN_ICONS
	if gold > 0 then return format("%d%s %d%s %d%s", gold, I.gold, silver, I.silver, c, I.copper) end
	if silver > 0 then return format("%d%s %d%s", silver, I.silver, c, I.copper) end
	return format("%d%s", c, I.copper)
end

function NS.SortedKeys(tbl)
	local keys = {}
	for k in pairs(tbl) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

--------------------------------------------------------------------------------
-- Slash commands.
--------------------------------------------------------------------------------
local function OnOff(value)
	return value and L["on"] or L["off"]
end

local function PrintHelp()
	NS.Print(L["Commands:"])
	NS.Print(L["/qam on|off - switch the automation on or off"])
	NS.Print(L["/qam pause - pause for this session (or hold Shift, Ctrl or Alt while talking to an NPC)"])
	NS.Print(L["/qam accept|turnin|trivial|repeatable|party|announce on|off - toggle one behaviour"])
	NS.Print(L["/qam reward fit|value|manual - how the reward is chosen"])
	NS.Print(L["/qam weapons on|off - let the addon pick weapons too"])
	NS.Print(L["/qam trinkets on|off - let the addon pick trinkets too"])
	NS.Print(L["/qam quality <1-5|off> - a reward of this quality or better is left to you (3 = rare)"])
	NS.Print(L["/qam stats <stat> [<stat>...] | default - the stats this character wants, most important first"])
	NS.Print(L["/qam ignore [npc|quest] - never automate the NPC or quest in front of you"])
	NS.Print(L["/qam ignore list | unignore <id> - review or clear the ignore lists"])
	NS.Print(L["/qam status - what would happen right now and why"])
	NS.Print(L["/qam why - explain the reward choice of the quest on screen"])
	NS.Print(L["/qam log [n] - show the last n log entries"])
	NS.Print(L["/qam settings - open the settings page"])
	NS.Print(L["/qam prepick on|off - ask when a quest is accepted; /qam pick - open the pick window for the selected quest"])
	NS.Print(L["/qam minimap - show or hide the minimap button"])
	NS.Print(L["/qam debug - print which APIs and events are active"])
end

-- Replaced by Settings.lua / Minimap.lua when they load.
function NS.OpenSettings()
	NS.Print(L["The settings page is not available on this client; use the /qam commands."])
end

function NS.ToggleMinimap()
	NS.Print(L["The minimap button is not loaded."])
end

local function ParseFlag(arg)
	arg = (arg or ""):lower()
	if arg == "on" or arg == "1" or arg == "true" or arg == "yes" then return true end
	if arg == "off" or arg == "0" or arg == "false" or arg == "no" then return false end
	return nil
end

function NS.SetFlag(key, arg, label)
	local settings = NS.db.settings
	local value = ParseFlag(arg)
	if value == nil then value = not settings[key] end
	settings[key] = value
	NS.Print("%s: %s", label, OnOff(value))
	NS.OnSettingsChanged()
	return value
end

local function SetChoice(key, list, arg, label, names)
	local settings = NS.db.settings
	arg = (arg or ""):lower()
	local value
	for _, v in ipairs(list) do
		if v:lower() == arg then value = v end
	end
	if value then settings[key] = value end
	local current = settings[key]
	NS.Print("%s: %s", label, names and names[current] or current)
	if not value and arg ~= "" then
		NS.Print(L["Valid values: %s"], table.concat(list, ", "):lower())
	end
	NS.OnSettingsChanged()
end

function NS.RewardModeName(mode)
	if mode == "fit" then return L["best fit for my class and level"] end
	if mode == "value" then return L["most valuable"] end
	return L["leave it to me"]
end

function NS.DebugReport()
	local version, build, buildDate, interface = GetBuildInfo()
	NS.Print("Quest Automator %s | client %s (%s, %s) | interface %s | locale %s | WOW_PROJECT_ID=%s",
		tostring(NS.version), tostring(version), tostring(build), tostring(buildDate),
		tostring(interface), tostring(GetLocale()), tostring(WOW_PROJECT_ID))
	NS.Print("APIs:")
	for _, path in ipairs(NS.SortedKeys(NS.features)) do
		NS.Print("  %s %s", NS.features[path] and "|cff40ff40ok|r     " or "|cffff4040missing|r", path)
	end
	NS.Print("Events:")
	for _, event in ipairs(NS.SortedKeys(NS.eventStatus)) do
		local status = NS.eventStatus[event]
		local color = status == "active" and "|cff40ff40" or "|cffff4040"
		local err = NS.eventErrors[event]
		NS.Print("  %s%s|r %s%s", color, status, event, err and (" |cffff8000last error: " .. err .. "|r") or "")
	end
	if NS.Client and NS.Client.DebugReport then NS.Client.DebugReport() end
	if NS.Rules and NS.Rules.DebugReport then NS.Rules.DebugReport() end
	if NS.Auto and NS.Auto.DebugReport then NS.Auto.DebugReport() end
	if NS.Glow and NS.Glow.DebugReport then NS.Glow.DebugReport() end
	if NS.Notice and NS.Notice.DebugReport then NS.Notice.DebugReport() end
	if NS.XPBar and NS.XPBar.DebugReport then NS.XPBar.DebugReport() end
	if NS.AuctionScore and NS.AuctionScore.DebugReport then NS.AuctionScore.DebugReport() end
	NS.Print("SavedVariables: account data from %s file, character data from %s file, character key %s, log entries %d",
		tostring(NS.svSource), tostring(NS.charSource), tostring(NS.CharKey()), NS.db and #NS.db.log or 0)
end

function NS.PrintLog(count)
	local log = NS.db.log
	count = count or 10
	if #log == 0 then
		NS.Print(L["The log is empty."])
		return
	end
	local first = math.max(1, #log - count + 1)
	for i = first, #log do
		local e = log[i]
		NS.Print("%s [%s] %s", date("%m-%d %H:%M:%S", e.t), tostring(e.kind), tostring(e.msg))
	end
end

function NS.PrintStatus()
	local s = NS.db.settings
	NS.Print(L["Automation: %s%s"], OnOff(s.enabled), (NS.Auto and NS.Auto.SessionPaused()) and (" (" .. L["paused for this session"] .. ")") or "")
	NS.Print(L["Accept quests: %s (low-level %s, repeatable %s) | hand in: %s (repeatable %s) | party escorts: %s"],
		OnOff(s.accept), OnOff(s.acceptTrivial), OnOff(s.acceptRepeatable), OnOff(s.turnIn), OnOff(s.turnInRepeatable), OnOff(s.confirmPartyQuests))
	NS.Print(L["Reward: %s | weapons: %s | trinkets: %s | no upgrade: %s"], NS.RewardModeName(s.rewardMode),
		OnOff(s.weapons), OnOff(s.trinkets), s.fallbackToValue and L["take the most valuable"] or L["leave it to me"])
	NS.Print(L["Left to me from quality: %s"], s.manualQuality >= 0 and NS.QualityName(s.manualQuality) or L["never"])
	NS.Print(L["Announcements: %s"], OnOff(s.announce))
	if NS.Rules and NS.Rules.PrintProfile then NS.Rules.PrintProfile() end
	if NS.Auto and NS.Auto.PrintContext then NS.Auto.PrintContext() end
end

SLASH_QUESTAUTOMATOR1 = "/qam"
SLASH_QUESTAUTOMATOR2 = "/questautomator"
SlashCmdList["QUESTAUTOMATOR"] = function(msg)
	msg = tostring(msg or "")
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	rest = rest or ""
	if not NS.loaded then
		NS.Print(L["Not loaded yet."])
		return
	end
	local s = NS.db.settings
	if cmd == "on" or cmd == "off" or cmd == "enable" or cmd == "disable" or cmd == "toggle" then
		local arg = (cmd == "on" or cmd == "enable") and "on" or ((cmd == "off" or cmd == "disable") and "off" or "")
		NS.SetFlag("enabled", arg, L["Automation"])
	elseif cmd == "pause" or cmd == "resume" then
		NS.Auto.SetSessionPaused(cmd == "pause" and (ParseFlag(rest) ~= false) or false)
	elseif cmd == "accept" then
		NS.SetFlag("accept", rest, L["Accept quests"])
	elseif cmd == "turnin" or cmd == "turn-in" or cmd == "complete" then
		NS.SetFlag("turnIn", rest, L["Hand in quests"])
	elseif cmd == "trivial" or cmd == "lowlevel" then
		NS.SetFlag("acceptTrivial", rest, L["Accept low-level quests"])
	elseif cmd == "repeatable" or cmd == "daily" then
		local value = NS.SetFlag("acceptRepeatable", rest, L["Accept repeatable quests"])
		s.turnInRepeatable = value
		NS.Print("%s: %s", L["Hand in repeatable quests"], OnOff(value))
		NS.OnSettingsChanged()
	elseif cmd == "party" or cmd == "escort" then
		NS.SetFlag("confirmPartyQuests", rest, L["Accept escorts started by the party"])
	elseif cmd == "announce" or cmd == "chat" then
		NS.SetFlag("announce", rest, L["Announcements"])
	elseif cmd == "reward" or cmd == "rewards" or cmd == "mode" then
		SetChoice("rewardMode", NS.REWARD_MODES, rest, L["Reward choice"],
			{ fit = NS.RewardModeName("fit"), value = NS.RewardModeName("value"), manual = NS.RewardModeName("manual") })
	elseif cmd == "weapons" then
		NS.SetFlag("weapons", rest, L["Pick weapons too"])
	elseif cmd == "trinkets" or cmd == "trinket" then
		NS.SetFlag("trinkets", rest, L["Pick trinkets too"])
	elseif cmd == "fallback" then
		NS.SetFlag("fallbackToValue", rest, L["No upgrade: take the most valuable"])
	elseif cmd == "quality" then
		local arg = rest:lower()
		if arg == "off" or arg == "never" or arg == "none" then
			s.manualQuality = -1
		elseif tonumber(arg) then
			local q = math.floor(tonumber(arg))
			if q < 0 then q = -1 end
			if q > 5 then q = 5 end
			s.manualQuality = q
		elseif arg ~= "" then
			NS.Print(L["Valid values: %s"], "off, 1 (" .. NS.QualityName(1) .. "), 2, 3, 4, 5 (" .. NS.QualityName(5) .. ")")
		end
		NS.Print("%s: %s", L["Left to me from quality"], s.manualQuality >= 0 and NS.QualityName(s.manualQuality) or L["never"])
		NS.OnSettingsChanged()
	elseif cmd == "stats" or cmd == "stat" then
		NS.Rules.StatsCommand(rest)
	elseif cmd == "ignore" then
		NS.Auto.IgnoreCommand(rest)
	elseif cmd == "unignore" then
		NS.Auto.UnignoreCommand(rest)
	elseif cmd == "status" or cmd == "" then
		NS.PrintStatus()
	elseif cmd == "log" then
		NS.PrintLog(tonumber(rest))
	elseif cmd == "pick" then
		if NS.PrePick then NS.PrePick.Command(rest) end
	elseif cmd == "prepick" then
		NS.SetFlag("prePickUI", rest, L["Ask me when I accept a quest"])
	elseif cmd == "settings" or cmd == "options" or cmd == "config" then
		NS.OpenSettings()
	elseif cmd == "minimap" then
		NS.ToggleMinimap()
	elseif cmd == "why" or cmd == "explain" then
		NS.Glow.Explain()
	elseif cmd == "debug" then
		NS.DebugReport()
	else
		PrintHelp()
	end
end

--------------------------------------------------------------------------------
-- Addon compartment (the drop-down next to the minimap on retail-style clients).
--------------------------------------------------------------------------------
function QuestAutomator_OnAddonCompartmentClick(_, buttonName)
	if not NS.loaded then return end
	if buttonName == "RightButton" then
		NS.OpenSettings()
	else
		if NS.PrePick then NS.PrePick.OpenAny() end
	end
end

function QuestAutomator_OnAddonCompartmentEnter(_, button)
	if not (GameTooltip and NS.loaded) then return end
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(L["Quest Automator"])
	GameTooltip:AddLine(format(L["Automation: %s%s"], OnOff(NS.db.settings.enabled), ""), 1, 1, 1)
	GameTooltip:AddLine(L["Left-click: pick window. Right-click: settings."], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function QuestAutomator_OnAddonCompartmentLeave()
	if GameTooltip then GameTooltip:Hide() end
end

--------------------------------------------------------------------------------
-- Lifecycle.
--------------------------------------------------------------------------------
NS.RegisterEvent("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	NS.InitDB()
end)
