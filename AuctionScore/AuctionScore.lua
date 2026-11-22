-- Quest Automator: the "AH score" bubble. Every equipment row in an auction-house
-- browse list gets a small green bubble, right-justified inside the name column,
-- with the stat-point gain over what the character wears in that slot:
--
--   [icon] Tough Leather Gloves of the Monkey            (+2.2)
--
-- Only upgrades show (gain > AuctionScore.MIN_DELTA); everything else is left as
-- Blizzard drew it. The number is the same scale Tooltip.lua and the pick window
-- use: Rewards.StatValue(item) - Rewards.WornItem(slot).value.
--
-- This file is the UI-independent part: scoring + cache, number formatting, the
-- bubble widget, and the PROVIDER registry. The auction UI differs per client and
-- per auction addon, so each one gets its own provider file that knows how to find
-- the name cell of a row and when it is repainted:
--
--   AuctionScore/AuctionScore_Forever.lua      Blizzard_AuctionHouseUI (TableBuilder cells)
--   AuctionScore/AuctionScore_ClassicEra.lua   Blizzard_AuctionUI (BrowseButtonN rows)
--   AuctionScore/AuctionScore_Auctionator.lua  Auctionator's own result list
--
-- A provider is a table:
--   { name = "forever",                 -- shown by /qam debug
--     addon = "Blizzard_AuctionHouseUI", -- Install() runs when this addon has loaded (ADDON_LOADED
--                                        -- or already loaded at PLAYER_LOGIN); nil = PLAYER_LOGIN
--     IsAvailable = function() -> bool,  -- the globals it hooks exist on this client
--     Install = function() -> bool }     -- hook the UI; call AuctionScore.Decorate(cell, text, itemRef) per row
-- Providers never read item data themselves and never create widgets; they map
-- "this row was painted" onto AuctionScore.Decorate / AuctionScore.Clear.
local ADDON, NS = ...
local L = NS.L
local Rules, Rewards = NS.Rules, NS.Rewards
local AuctionScore = {}
NS.AuctionScore = AuctionScore

AuctionScore.MIN_DELTA = 0.1          -- a gain must exceed this to get a bubble
AuctionScore.BUBBLE_HEIGHT = 14
AuctionScore.BUBBLE_PAD = 4           -- horizontal padding inside the bubble, each side
AuctionScore.BUBBLE_GAP = 3           -- space between the name text and the bubble
AuctionScore.COLOR_TEXT = { 0.25, 1, 0.25 }
AuctionScore.COLOR_BG = { 0.05, 0.25, 0.05, 0.9 }
AuctionScore.COLOR_BORDER = { 0.25, 0.8, 0.25, 0.9 }

--------------------------------------------------------------------------------
-- Formatting: one decimal, always signed, nil when not worth showing.
--   AuctionScore.Format(1.23) -> "+1.2"   Format(12.25) -> "+12.3"   Format(0.1) -> nil
--------------------------------------------------------------------------------
function AuctionScore.Format(delta)
	delta = tonumber(delta)
	if not delta or delta <= AuctionScore.MIN_DELTA then return nil end
	return string.format("+%.1f", delta)
end

--------------------------------------------------------------------------------
-- Scoring. An item is identified the way auction lists identify it: itemID plus
-- the itemLevel / itemSuffix of that particular listing ("of the Monkey" is a
-- suffix, and its stats are not those of the bare itemID). A full hyperlink can be
-- passed instead when the UI has one (Era's GetAuctionItemLink).
--
-- Result: nil while item data is still loading (the caller may retry on
-- GET_ITEM_INFO_RECEIVED), else { wearable, value, wornValue, gain, upgrade }.
--------------------------------------------------------------------------------
local cache = {}        -- key -> result table or false (not equipment / cannot wear)

function AuctionScore.Invalidate()
	cache = {}
end

local function Key(itemID, itemLevel, itemSuffix, link)
	if link then return link end
	return tostring(itemID) .. ":" .. tostring(itemLevel or 0) .. ":" .. tostring(itemSuffix or 0)
end

-- Stats of the listing. A suffixed listing ("Medicine Staff of Power") needs the
-- itemKey tooltip: the link GetItemInfo builds from a bare itemID has NO suffix, so
-- falling back to it scores the stat-less base weapon and every "of X" variant gets
-- the same number (owner 2026-11-22: twenty staffs, all +12.5). When the keyed
-- tooltip has not loaded yet, return nil = pending; the provider retries on
-- ITEM_KEY_ITEM_INFO_RECEIVED / GET_ITEM_INFO_RECEIVED. Only an unsuffixed listing
-- may use the bare-itemID path.
local function ListingStats(itemID, itemLevel, itemSuffix, link)
	if link then return Rewards.WornItemStats(link) end
	local suffixed = (itemSuffix or 0) ~= 0
	if suffixed or (itemLevel or 0) ~= 0 then
		local data = NS.Call("C_TooltipInfo.GetItemKey", itemID, itemLevel or 0, itemSuffix or 0)
		local stats = data and Rewards.StatsFromTooltipData(data)
		if stats then return stats end
		if suffixed then return nil end -- pending: never score a suffixed listing as its base item
	end
	local _, infoLink = NS.Call("C_Item.GetItemInfo", itemID)
	infoLink = NS.SafeString(infoLink)
	if not infoLink then return nil end -- not loaded yet
	return Rewards.WornItemStats(infoLink)
end

function AuctionScore.Score(itemID, itemLevel, itemSuffix, link)
	itemID = NS.SafeNumber(itemID)
	if not itemID and link then itemID = NS.SafeNumber(NS.Call("C_Item.GetItemInfoInstant", link)) end
	if not itemID then return false end
	local key = Key(itemID, itemLevel, itemSuffix, link)
	local hit = cache[key]
	if hit ~= nil then return hit end

	local _, _, _, equipLoc, _, classID, subclassID = NS.Call("C_Item.GetItemInfoInstant", link or itemID)
	equipLoc, classID, subclassID = NS.SafeString(equipLoc), NS.SafeNumber(classID), NS.SafeNumber(subclassID)
	if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_BAG" or equipLoc == "INVTYPE_NON_EQUIP"
		or (classID ~= Rules.CLASS_ARMOR and not Rules.IsWeapon(classID, subclassID)) then
		cache[key] = false
		return false
	end
	local stats = ListingStats(itemID, itemLevel, itemSuffix, link)
	if not stats then return nil end -- pending: not cached, so the next paint retries

	local player = Rules.Player()
	local c = { classID = classID, subclassID = subclassID, equipLoc = equipLoc, usable = true, stats = stats }
	local fit = Rewards.FitScore(c, player, NS.db and NS.db.settings or {})
	if (fit.typeScore or 0) <= 0 then
		cache[key] = false
		return false
	end
	local weaponSubclass = Rules.IsWeapon(classID, subclassID) and subclassID or nil
	local value = Rewards.StatValue(stats, player, weaponSubclass)
	local worn = Rewards.WornItem(equipLoc, player)
	if worn == nil then return nil end -- worn item data not loaded yet
	local result = { wearable = true, value = value, wornValue = worn.value or 0 }
	result.gain = value - result.wornValue
	result.upgrade = result.gain > AuctionScore.MIN_DELTA
	cache[key] = result
	return result
end

--------------------------------------------------------------------------------
-- The bubble widget. One per name cell, created on first use and parked on the
-- cell as cell.qamScoreBubble. AuctionScore.Decorate places it and re-anchors the
-- name text so the two never overlap; AuctionScore.Clear hides it and restores the
-- text's original right anchor.
--
--   cell      the frame the bubble lives in (the name column cell / row button)
--   text      the FontString holding the item name; its RIGHT point is moved
--   neighbour optional second FontString Blizzard also anchors on the right
--             (Forever's ExtraInfo); it is shifted left of the bubble too
--------------------------------------------------------------------------------
local function CreateBubble(cell)
	local bubble = CreateFrame("Frame", nil, cell, BackdropTemplateMixin and "BackdropTemplate" or nil)
	bubble:SetHeight(AuctionScore.BUBBLE_HEIGHT)
	bubble:SetFrameLevel((cell:GetFrameLevel() or 0) + 2)
	if bubble.SetBackdrop then
		bubble:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
		bubble:SetBackdropColor(unpack(AuctionScore.COLOR_BG))
		bubble:SetBackdropBorderColor(unpack(AuctionScore.COLOR_BORDER))
	end
	local fs = bubble:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("CENTER", bubble, "CENTER", 0, 0)
	fs:SetJustifyH("CENTER")
	fs:SetTextColor(unpack(AuctionScore.COLOR_TEXT))
	bubble.text = fs
	bubble:Hide()
	return bubble
end

-- Remember where the text's RIGHT point was before we moved it, once per cell.
local function RememberRight(cell, text)
	if cell.qamScoreSavedRight or not text or not text.GetPoint then return end
	for i = 1, (text:GetNumPoints() or 0) do
		local point, rel, relPoint, x, y = text:GetPoint(i)
		if point == "RIGHT" then
			cell.qamScoreSavedRight = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
			return
		end
	end
	cell.qamScoreSavedRight = { rel = cell, relPoint = "RIGHT", x = 0, y = 0 }
end

local function RestoreRight(cell, text)
	local saved = cell.qamScoreSavedRight
	if saved and text then text:SetPoint("RIGHT", saved.rel or cell, saved.relPoint or "RIGHT", saved.x, saved.y) end
end

-- Show the bubble with `label` and push the text(s) left of it.
function AuctionScore.Place(cell, text, label, neighbour)
	local bubble = cell.qamScoreBubble
	if not bubble then
		bubble = CreateBubble(cell)
		cell.qamScoreBubble = bubble
	end
	bubble.text:SetText(label)
	bubble:SetWidth(math.ceil(bubble.text:GetStringWidth()) + 2 * AuctionScore.BUBBLE_PAD)
	bubble:ClearAllPoints()
	bubble:SetPoint("RIGHT", cell, "RIGHT", -1, 0)
	bubble:Show()
	RememberRight(cell, text)
	local leftOfBubble = bubble
	if neighbour then
		neighbour:SetPoint("RIGHT", bubble, "LEFT", -AuctionScore.BUBBLE_GAP, 0)
		if neighbour:IsShown() then leftOfBubble = neighbour end
	end
	if text then text:SetPoint("RIGHT", leftOfBubble, "LEFT", -AuctionScore.BUBBLE_GAP, 0) end
end

-- Hide the bubble and give the text its original right edge back.
function AuctionScore.Clear(cell, text, neighbour)
	local bubble = cell.qamScoreBubble
	if not bubble or not bubble:IsShown() then return end
	bubble:Hide()
	if neighbour and cell.qamScoreSavedRight then
		local s = cell.qamScoreSavedRight
		neighbour:SetPoint("RIGHT", cell, "RIGHT", s.x, 0)
	end
	RestoreRight(cell, text)
end

-- The one call a provider makes per painted row. itemRef is
-- { itemID, itemLevel, itemSuffix } or { link = "|Hitem:..." }.
-- Returns the score result (nil = pending, false = not an upgrade candidate).
function AuctionScore.Decorate(cell, text, itemRef, neighbour)
	if not NS.loaded or not NS.db.settings.ahScore then
		AuctionScore.Clear(cell, text, neighbour)
		return false
	end
	local ok, result = pcall(AuctionScore.Score, itemRef.itemID, itemRef.itemLevel, itemRef.itemSuffix, itemRef.link)
	if not ok then
		NS.WarnOnce("ahscore", tostring(result))
		AuctionScore.Clear(cell, text, neighbour)
		return false
	end
	local label = result and AuctionScore.Format(result.gain) or nil
	if label then
		AuctionScore.Place(cell, text, label, neighbour)
	else
		AuctionScore.Clear(cell, text, neighbour)
	end
	return result
end

--------------------------------------------------------------------------------
-- Providers.
--------------------------------------------------------------------------------
AuctionScore.PROVIDER_INTERFACE = { "name", "IsAvailable", "Install" }
AuctionScore.providers = {}   -- name -> provider
AuctionScore.installed = {}   -- name -> true once Install() returned true

function AuctionScore.Register(provider)
	for _, field in ipairs(AuctionScore.PROVIDER_INTERFACE) do
		if provider[field] == nil then
			NS.WarnOnce("ahscore-provider:" .. tostring(provider.name) .. ":" .. field, "AuctionScore provider " .. tostring(provider.name) .. " is missing " .. field)
			return false
		end
	end
	AuctionScore.providers[provider.name] = provider
	return true
end

local function TryInstall(provider)
	if AuctionScore.installed[provider.name] then return true end
	local okAvail, available = pcall(provider.IsAvailable)
	if not okAvail or not available then return false end
	local ok, result = pcall(provider.Install)
	if not ok then
		NS.WarnOnce("ahscore-install:" .. provider.name, provider.name .. " -> " .. tostring(result))
		return false
	end
	if result then
		AuctionScore.installed[provider.name] = true
		NS.features["AuctionScore." .. provider.name] = true
	end
	return result and true or false
end

local function IsAddonLoaded(name)
	local loaded = NS.Call("C_AddOns.IsAddOnLoaded", name)
	if loaded == nil then loaded = NS.Call("IsAddOnLoaded", name) end
	return loaded == true or loaded == 1
end

-- Install every provider whose trigger addon is loaded (or has no trigger).
function AuctionScore.InstallReady(justLoadedAddon)
	for _, provider in pairs(AuctionScore.providers) do
		if provider.addon == nil or provider.addon == justLoadedAddon or IsAddonLoaded(provider.addon) then
			TryInstall(provider)
		end
	end
end

function AuctionScore.DebugReport()
	for _, name in ipairs(NS.SortedKeys(AuctionScore.providers)) do
		NS.Print("  AuctionScore %s: %s", name, AuctionScore.installed[name] and "|cff40ff40installed|r" or "|cff808080not installed|r")
	end
end

NS.RegisterEvent("PLAYER_LOGIN", function() AuctionScore.InstallReady(nil) end)
NS.RegisterEvent("ADDON_LOADED", function(name) if NS.loaded then AuctionScore.InstallReady(name) end end)
for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
	NS.RegisterEvent(event, AuctionScore.Invalidate)
end