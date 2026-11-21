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
	local out = { wearable = true, value = value, untrained = fit.untrained, player = player }
	-- The item being hovered may BE the worn one (character panel, or a bag item of
	-- the same kind): comparing it with itself says nothing, so only the score shows.
	local isWorn = worn and worn.link == link
	if worn and not worn.empty and not isWorn then
		out.wornValue = worn.value
		out.gain = value - worn.value
		-- The same margin the hand-in uses (settings.upgradeBand percent).
		local band = (tonumber(NS.db.settings.upgradeBand) or 10) / 100
		out.upgrade = worn.value <= 0 and value > 0 or out.gain >= worn.value * band
	end
	return out
end

function Tooltip.Line(info)
	local left = Tooltip.PREFIX_COLOR .. L["Quest Automator"] .. "|r"
	if not info.wearable then
		return left, "|cff808080" .. L["cannot wear"] .. "|r"
	end
	local right
	if info.gain ~= nil then
		local color = info.upgrade and "|cff40ff40" or (info.gain < 0 and "|cffff4040" or "|cffb0b0b0")
		local sign = info.gain >= 0 and "+" or ""
		right = string.format("%s%s%s|r   %s %s %s", color, sign, Fmt(info.gain), Fmt(info.value), info.gain >= 0 and ">" or "<", Fmt(info.wornValue))
	else
		right = Fmt(info.value)
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
	tooltip:AddDoubleLine(left, right)
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
