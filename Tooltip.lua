-- Quest Automator: one line on every equipment tooltip showing how the reward
-- scorer values the item for this character, against what is worn in its slot:
--
--   Quest Automator  +2.0   12.2 > 10.2        (an upgrade)
--   Quest Automator  -3.5    6.7 < 10.2        (worse than what is worn)
--   Quest Automator  12.2   (empty slot)
--   Quest Automator  cannot wear
--
-- Same stat values and worn-item lookup the picker and the automation use
-- (Rewards.StatValue / Rewards.WornItem), so what the tooltip says is what the
-- hand-in would do. Setting: settings.tooltipScore (default on).
local ADDON, NS = ...
local L = NS.L
local Rules, Rewards = NS.Rules, NS.Rewards
local Tooltip = {}
NS.Tooltip = Tooltip

Tooltip.PREFIX_COLOR = "|cff4fc3f7"

local function ClassColorOf(player)
	local colors = RAID_CLASS_COLORS and RAID_CLASS_COLORS[player.class or ""]
	if colors and colors.colorStr then return "|c" .. colors.colorStr end
	return "|cffffffff"
end

local function Fmt(v)
	if v == math.floor(v) then return string.format("%d", v) end
	return string.format("%.1f", v)
end

-- The delta drawn the way the AH bubble draws it: bracketed, in the bubble's green when
-- it is an upgrade, red when worse, grey when flat. A tooltip cannot host a frame, so the
-- "bubble" is the bracketed text; the raw scores follow dimmed so the number still explains itself.
local BUBBLE_UP, BUBBLE_DOWN, BUBBLE_FLAT, DIM = "|cff40ff40", "|cffff4040", "|cffb0b0b0", "|cff808080"

local function Delta(info)
	local color = info.upgrade and BUBBLE_UP or (info.gain < 0 and BUBBLE_DOWN or BUBBLE_FLAT)
	local sign = info.gain >= 0 and "+" or ""
	return string.format("%s[ %s%s ]|r", color, sign, Fmt(info.gain))
end

-- The item facts the scorer needs, from a hyperlink. nil when it is not equipment
-- or the item data has not loaded.
function Tooltip.Describe(link)
	if not link or not NS.db or not NS.db.settings.tooltipScore then return nil end
	local _, _, _, equipLoc, _, classID, subclassID = NS.Call("C_Item.GetItemInfoInstant", link)
	equipLoc, classID, subclassID = NS.SafeString(equipLoc), NS.SafeNumber(classID), NS.SafeNumber(subclassID)
	if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_BAG" or equipLoc == "INVTYPE_NON_EQUIP" then return nil end
	if classID ~= Rules.CLASS_ARMOR and not Rules.IsWeapon(classID, subclassID) then return nil end
	local player = Rules.Player()
	local c = { classID = classID, subclassID = subclassID, equipLoc = equipLoc, usable = true, stats = Rewards.WornItemStats(link) }
	local fit = Rewards.FitScore(c, player, NS.db.settings)
	if (fit.typeScore or 0) <= 0 then
		return { wearable = false, why = fit.why }
	end
	local weaponSubclass = Rules.IsWeapon(classID, subclassID) and subclassID or nil
	local value = Rewards.StatValue(c.stats, player, weaponSubclass)
	local worn = Rewards.WornItem(equipLoc, player)
	local out = { wearable = true, value = value, untrained = fit.untrained, player = player,
		stats = c.stats, weaponSubclass = weaponSubclass, fit = fit, link = link }
	-- The item being hovered may BE the worn one (character panel, or a bag item of
	-- the same kind): comparing it with itself says nothing, so only the score shows.
	local isWorn = worn and worn.link == link
	if worn and not worn.empty and not isWorn then
		out.wornValue = worn.value
		out.worn = worn
		out.gain = value - worn.value
		-- The same margin the hand-in uses (settings.upgradeBand percent).
		local band = (tonumber(NS.db.settings.upgradeBand) or 10) / 100
		out.band = band
		out.upgrade = worn.value <= 0 and value > 0 or out.gain >= worn.value * band
	end
	return out
end

function Tooltip.ShiftHeld()
	local ok, held = pcall(function() return IsShiftKeyDown and IsShiftKeyDown() end)
	return ok and held == true
end

-- One "amount x weight = value" row per stat the class has a weight for, sorted by
-- value, then the stats that counted for nothing (weight 0), then the total.
local function StatRows(rows, stats, player, weaponSubclass, indent)
	local parts, ignored = {}, {}
	for key, amount in pairs(stats or {}) do
		local weight = Rewards.WeightFor(player, key, weaponSubclass)
		if weight ~= 0 and amount and amount ~= 0 then
			parts[#parts + 1] = { key = key, amount = amount, weight = weight, value = weight * amount }
		elseif amount and amount ~= 0 then
			ignored[#ignored + 1] = Rules.StatName(key)
		end
	end
	table.sort(parts, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.key < b.key
	end)
	for _, p in ipairs(parts) do
		rows[#rows + 1] = { indent .. Rules.StatName(p.key),
			string.format("%s%s x %s = %s|r", DIM, Fmt(p.amount), Fmt(p.weight), Fmt(p.value)) }
	end
	if #ignored > 0 then
		table.sort(ignored)
		rows[#rows + 1] = { indent .. DIM .. L["no weight"] .. "|r", DIM .. table.concat(ignored, ", ") .. "|r" }
	end
end

-- The full computation behind Tooltip.Line, as { left, right } pairs (Shift held).
function Tooltip.BreakdownRows(info)
	local rows = {}
	local player = info.player
	local profile = player.profileName or player.profile or ""
	rows[#rows + 1] = { DIM .. L["weights"] .. "|r", DIM .. tostring(player.class or "?") .. (profile ~= "" and (" / " .. tostring(profile)) or "") .. "|r" }
	rows[#rows + 1] = { DIM .. L["this item"] .. "|r", DIM .. Fmt(info.value) .. "|r" }
	StatRows(rows, info.stats, player, info.weaponSubclass, "  ")
	if info.fit and info.fit.typeScore and info.fit.typeScore < 1 then
		rows[#rows + 1] = { "  " .. DIM .. L["type factor (hand-in only)"] .. "|r", DIM .. Fmt(info.fit.typeScore) .. "|r" }
	end
	if info.worn then
		rows[#rows + 1] = { DIM .. L["worn"] .. "|r", DIM .. Fmt(info.wornValue) .. "|r" }
		StatRows(rows, info.worn.stats, player, info.weaponSubclass, "  ")
		rows[#rows + 1] = { DIM .. L["upgrade band"] .. "|r",
			string.format("%s%d%% of %s = %s|r", DIM, math.floor((info.band or 0) * 100 + 0.5), Fmt(info.wornValue), Fmt(info.wornValue * (info.band or 0))) }
	end
	return rows
end

function Tooltip.Line(info)
	local left = Tooltip.PREFIX_COLOR .. L["Quest Automator"] .. "|r"
	if not info.wearable then
		return left, DIM .. L["cannot wear"] .. "|r"
	end
	local right
	if info.gain ~= nil then
		right = string.format("%s  %s%s %s %s|r", Delta(info), DIM, Fmt(info.value), info.gain >= 0 and ">" or "<", Fmt(info.wornValue))
	else
		right = DIM .. Fmt(info.value) .. "|r"
	end
	if info.untrained then right = right .. "  |cffff9933" .. L["needs weapon training"] .. "|r" end
	return left, right
end

local function OnItem(tooltip, data)
	if not NS.loaded or not tooltip or type(tooltip.GetItem) ~= "function" then return end
	local link
	if type(data) == "table" and data.hyperlink then link = NS.SafeString(data.hyperlink) end
	if not link then
		local _, itemLink = tooltip:GetItem()
		link = NS.SafeString(itemLink)
	end
	if not link then return end
	local ok, info = pcall(Tooltip.Describe, link)
	if not ok then NS.WarnOnce("tooltip", tostring(info)) return end
	if not info then return end
	local left, right = Tooltip.Line(info)
	-- a blank line sets our row apart from the item's own stat block and other addons' lines
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine(left, right)
	-- Shift held: the full computation, so a surprising verdict can be checked against
	-- the weights (e.g. armour points dwarfing a few points of a wanted stat).
	if info.wearable and Tooltip.ShiftHeld() then
		for _, row in ipairs(Tooltip.BreakdownRows(info)) do
			tooltip:AddDoubleLine(row[1], row[2])
		end
	end
	if tooltip.Show then tooltip:Show() end
end

function Tooltip.Install()
	if Tooltip.installed then return end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
		NS.features["TooltipDataProcessor"] = true
	else
		NS.features["TooltipDataProcessor"] = false
		for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
			local tt = _G[name]
			if tt and tt.HookScript then tt:HookScript("OnTooltipSetItem", OnItem) end
		end
	end
	Tooltip.installed = true
end

NS.RegisterEvent("PLAYER_LOGIN", Tooltip.Install)
