-- QuestAutomator: core namespace, feature detection, saved variables,
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
	-- Reward priority engine (Engine.lua, spec §6). Each tier: "auto" or "recommend".
	tier1Action = "recommend", -- hard to value: trinket, relic, Use / proc effect, not equipment
	tier2Action = "auto",      -- one wearable reward is a clear upgrade (ilvl > worn + ilvlBand)
	tier3Action = "auto",      -- one wearable reward is a sidegrade (within ilvlBand of worn)
	tier4Action = "recommend", -- two or more rewards are upgrades or sidegrades
	tier5Action = "auto",      -- nothing wearable: the most valuable reward
	ilvlBand = 2,              -- item levels either side of the worn piece that count as a sidegrade
	weaponProficiency = "learnable", -- "learnable" (the class can train it) or "usable" (the character has the skill)
	valueSource = "vendor",    -- "vendor" | "auction" | "disenchant" (the latter two fall back to vendor without a provider)
	prePickUI = true,          -- show the pick window when a quest with a recommend-tier reward is accepted
	manualQuality = 3,         -- a reward of this quality or better is left to the player (-1 = never); 3 = Rare
	modifier = "SHIFT",        -- key that pauses the automation while held: SHIFT, CTRL, ALT, NONE
	announce = true,           -- chat line for every quest accepted, handed in and reward chosen
	minimap = true,            -- minimap button
	xpBar = true,              -- completed quests' experience on the experience bar (XPBar.lua)
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

NS.TIER_ACTIONS = { "recommend", "auto" }
NS.WEAPON_PROFICIENCIES = { "learnable", "usable" }
NS.VALUE_SOURCES = { "vendor", "auction", "disenchant" }
NS.MODIFIERS = { "SHIFT", "CTRL", "ALT", "NONE" }
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
	-- Removed with the priority engine (QuestAutomator fork): the upstream reward
	-- mode and its kind switches. The tiers replace them.
	settings.rewardMode, settings.weapons, settings.trinkets, settings.fallbackToValue = nil, nil, nil, nil
	settings.weaponOffered, settings.trinketOffered = nil, nil
	for _, key in ipairs({ "tier1Action", "tier2Action", "tier3Action", "tier4Action", "tier5Action" }) do
		if not Contains(NS.TIER_ACTIONS, settings[key]) then settings[key] = NS.DEFAULT_SETTINGS[key] end
	end
	if not Contains(NS.WEAPON_PROFICIENCIES, settings.weaponProficiency) then settings.weaponProficiency = NS.DEFAULT_SETTINGS.weaponProficiency end
	if not Contains(NS.VALUE_SOURCES, settings.valueSource) then settings.valueSource = NS.DEFAULT_SETTINGS.valueSource end
	settings.ilvlBand = tonumber(settings.ilvlBand) or NS.DEFAULT_SETTINGS.ilvlBand
	if settings.ilvlBand < 0 then settings.ilvlBand = 0 end
	if settings.ilvlBand > 20 then settings.ilvlBand = 20 end
	if not Contains(NS.MODIFIERS, settings.modifier) then settings.modifier = NS.DEFAULT_SETTINGS.modifier end
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
	cdb.prePicks = type(cdb.prePicks) == "table" and cdb.prePicks or {} -- questID -> itemID chosen at accept time (pre-pick UI)
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
function NS.FormatMoney(copper)
	copper = math.floor((tonumber(copper) or 0) + 0.5)
	if copper < 0 then copper = 0 end
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local c = copper % 100
	if gold > 0 then return format(L["%dg %ds %dc"], gold, silver, c) end
	if silver > 0 then return format(L["%ds %dc"], silver, c) end
	return format(L["%dc"], c)
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
	NS.Print(L["/qam pause - pause for this session (or hold the modifier key while talking to an NPC)"])
	NS.Print(L["/qam accept|turnin|trivial|repeatable|party|announce on|off - toggle one behaviour"])
	NS.Print(L["/qam tier [1-5 auto|recommend] - how each reward tier is handled (1 hard to value, 2 upgrade, 3 sidegrade, 4 several, 5 most valuable)"])
	NS.Print(L["/qam band <0-20> - item levels either side of your gear that count as a sidegrade"])
	NS.Print(L["/qam weaponskill learnable|usable - which weapons count as wearable"])
	NS.Print(L["/qam value vendor|auction|disenchant - what most valuable means"])
	NS.Print(L["/qam prepick on|off - ask when a quest is accepted; /qam pick - open the pick window for the selected quest"])
	NS.Print(L["/qam quality <1-5|off> - a reward of this quality or better is left to you (3 = rare)"])
	NS.Print(L["/qam modifier shift|ctrl|alt|none - key that pauses the automation while held"])
	NS.Print(L["/qam stats <stat> [<stat>...] | default - the stats this character wants, most important first"])
	NS.Print(L["/qam ignore [npc|quest] - never automate the NPC or quest in front of you"])
	NS.Print(L["/qam ignore list | unignore <id> - review or clear the ignore lists"])
	NS.Print(L["/qam status - what would happen right now and why"])
	NS.Print(L["/qam why - explain the reward choice of the quest on screen"])
	NS.Print(L["/qam log [n] - show the last n log entries"])
	NS.Print(L["/qam settings - open the settings page"])
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

function NS.DebugReport()
	local version, build, buildDate, interface = GetBuildInfo()
	NS.Print("QuestAutomator %s | client %s (%s, %s) | interface %s | locale %s | WOW_PROJECT_ID=%s",
		tostring(NS.version), tostring(version), tostring(build), tostring(buildDate),
		tostring(interface), tostring(GetLocale()), tostring(WOW_PROJECT_ID))
	if NS.Client and NS.Client.DebugReport then NS.Client.DebugReport() end
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
	if NS.Rules and NS.Rules.DebugReport then NS.Rules.DebugReport() end
	if NS.Auto and NS.Auto.DebugReport then NS.Auto.DebugReport() end
	if NS.Glow and NS.Glow.DebugReport then NS.Glow.DebugReport() end
	if NS.PrePick and NS.PrePick.DebugReport then NS.PrePick.DebugReport() end
	if NS.XPBar and NS.XPBar.DebugReport then NS.XPBar.DebugReport() end
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
	NS.PrintTiers()
	NS.Print(L["Sidegrade band: %d item levels | wearable weapons: %s | most valuable means: %s | ask on accept: %s"], s.ilvlBand,
		s.weaponProficiency == "usable" and L["weapons I have trained"] or L["weapons my class can learn"],
		s.valueSource == "auction" and L["auction value"] or (s.valueSource == "disenchant" and L["disenchant value"] or L["vendor price"]),
		OnOff(s.prePickUI))
	NS.Print(L["Left to me from quality: %s"], s.manualQuality >= 0 and NS.QualityName(s.manualQuality) or L["never"])
	NS.Print(L["Pause key: %s | announcements: %s"], s.modifier, OnOff(s.announce))
	if NS.Rules and NS.Rules.PrintProfile then NS.Rules.PrintProfile() end
	if NS.Auto and NS.Auto.PrintContext then NS.Auto.PrintContext() end
end

function NS.TierActionNames()
	return { auto = L["pick it automatically"], recommend = L["recommend only (glow, window stays open)"] }
end

-- "auto 2 3 5 / ask 1 4" for tooltips.
function NS.TierSummaryShort()
	local s = NS.db.settings
	local auto, ask = {}, {}
	for _, n in ipairs({ "1", "2", "3", "4", "5" }) do
		if s[NS.Engine.TIER_SETTING[n]] == "auto" then auto[#auto + 1] = n else ask[#ask + 1] = n end
	end
	return string.format("%s %s / %s %s", L["auto"], table.concat(auto, " "), L["recommend"], table.concat(ask, " "))
end

function NS.PrintTiers()
	local s = NS.db.settings
	local names = NS.TierActionNames()
	local bits = {}
	for _, n in ipairs({ "1", "2", "3", "4", "5" }) do
		local action = s[NS.Engine.TIER_SETTING[n]]
		bits[#bits + 1] = string.format("%s %s=%s", n, NS.Engine.TierName(n), action == "auto" and L["auto"] or L["recommend"])
	end
	NS.Print(L["Reward tiers: %s"], table.concat(bits, " | "))
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
	elseif cmd == "tier" or cmd == "tiers" then
		-- /qam tier            -> list;  /qam tier 3 auto|recommend
		local n, action = rest:match("^(%d)%s*(%a*)$")
		if n and NS.Engine.TIER_SETTING[n] then
			if action ~= "" then
				SetChoice(NS.Engine.TIER_SETTING[n], NS.TIER_ACTIONS, action, L["Tier %s (%s)"]:format(n, NS.Engine.TierName(n)), NS.TierActionNames())
			else
				NS.Print("%s: %s", L["Tier %s (%s)"]:format(n, NS.Engine.TierName(n)), NS.TierActionNames()[s[NS.Engine.TIER_SETTING[n]]])
			end
		else
			NS.PrintTiers()
		end
	elseif cmd == "band" or cmd == "ilvl" then
		local v = tonumber(rest)
		if v then
			s.ilvlBand = math.max(0, math.min(20, math.floor(v)))
			NS.OnSettingsChanged()
		elseif rest ~= "" then
			NS.Print(L["Valid values: %s"], "0-20")
		end
		NS.Print("%s: %d", L["Sidegrade band (item levels)"], s.ilvlBand)
	elseif cmd == "weaponskill" or cmd == "weapons" then
		SetChoice("weaponProficiency", NS.WEAPON_PROFICIENCIES, rest, L["Wearable weapons"],
			{ learnable = L["weapons my class can learn"], usable = L["weapons I have trained"] })
	elseif cmd == "value" then
		SetChoice("valueSource", NS.VALUE_SOURCES, rest, L["Most valuable means"],
			{ vendor = L["vendor price"], auction = L["auction value"], disenchant = L["disenchant value"] })
	elseif cmd == "prepick" or cmd == "ask" then
		NS.SetFlag("prePickUI", rest, L["Ask me when I accept a quest"])
	elseif cmd == "pick" then
		if NS.PrePick and NS.PrePick.Command then NS.PrePick.Command(rest) else NS.Print(L["The pick window is not loaded."]) end
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
	elseif cmd == "modifier" or cmd == "key" then
		SetChoice("modifier", NS.MODIFIERS, rest:upper(), L["Pause key"])
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
		NS.SetFlag("enabled", "", L["Automation"])
	end
end

function QuestAutomator_OnAddonCompartmentEnter(_, button)
	if not (GameTooltip and NS.loaded) then return end
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(L["QuestAutomator"])
	GameTooltip:AddLine(format(L["Automation: %s%s"], OnOff(NS.db.settings.enabled), ""), 1, 1, 1)
	GameTooltip:AddLine(L["Left-click: switch on or off. Right-click: settings."], 0.8, 0.8, 0.8)
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
