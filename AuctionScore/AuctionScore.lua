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
-- Two palettes: EXACT (green) when the stats are the listing's own; ESTIMATE
-- (yellow) when a suffixed listing is scored on its base item until hovered.
AuctionScore.EXACT    = { text = { 0.25, 1, 0.25 },  bg = { 0.05, 0.25, 0.05, 0.9 }, border = { 0.25, 0.8, 0.25, 0.9 } }
AuctionScore.ESTIMATE = { text = { 1, 0.85, 0.3 },   bg = { 0.28, 0.22, 0.04, 0.9 }, border = { 0.85, 0.7, 0.25, 0.9 } }
-- Kept for anything outside that read the old names.
AuctionScore.COLOR_TEXT, AuctionScore.COLOR_BG, AuctionScore.COLOR_BORDER = AuctionScore.EXACT.text, AuctionScore.EXACT.bg, AuctionScore.EXACT.border

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
-- GET_ITEM_INFO_RECEIVED), else { wearable, value, wornValue, gain, upgrade, estimate }.
--
-- SUFFIXED LISTINGS (owner design 2026-11-22). From addon code the client will NOT
-- resolve a random-suffix roll for a browse key: C_TooltipInfo.GetItemKey and a
-- scanning GameTooltip:SetItemKey both return the group placeholder ("Items in this
-- group may vary in stats and appearance") with DPS only - verified for every suffix
-- of five weapon groups on Forever 1.60.1 (71037). Blizzard's own hover tooltip,
-- called from secure code, gets the full item. So:
--   1. A suffixed row is first scored on its BASE item (bare itemID: weapon DPS,
--      armour value, no suffix stats) and drawn as a YELLOW "estimate" bubble.
--   2. Every item tooltip the player opens is watched (TooltipDataProcessor). When
--      one carries a suffixed link, its stats are parsed and kept in a session
--      capture DB keyed by itemID:itemLevel:suffix, and rows showing that key are
--      repainted with the exact GREEN bubble.
-- The capture DB is never persisted; it is rebuilt by hovering.
--------------------------------------------------------------------------------
local cache = {}        -- key -> result table or false (not equipment / cannot wear)
local captured = {}     -- fallback capture table before NS.db exists; see Captured()
local liveCells = setmetatable({}, { __mode = "k" }) -- cell -> true, for repaint after a capture
local Captured, SameStats -- forward declarations (defined below the capture section)

function AuctionScore.Invalidate()
	cache = {}
end

-- A stat-profile switch: every score is stale (same items, different weights). Drop the
-- score cache - NOT the captured suffix stats, which are item data - and re-Decorate
-- every live cell so the numbers and yellow/green states refresh without a new search.
function AuctionScore.OnProfileChanged()
	AuctionScore.Invalidate()
	for cell in pairs(liveCells) do
		if cell:IsShown() and cell.qamScoreRef then
			AuctionScore.Decorate(cell, cell.qamScoreText, cell.qamScoreRef, cell.qamScoreNeighbour)
		end
	end
	if AuctionScore.switcher then AuctionScore.switcher:Update() end
end
local function Key(itemID, itemLevel, itemSuffix, link)
	if link then return link end
	return tostring(itemID) .. ":" .. tostring(itemLevel or 0) .. ":" .. tostring(itemSuffix or 0)
end

-- The DURABLE capture key: "itemID:itemLevel:Display Name". The display name
-- ("Medicine Staff of Power") carries the roll and is the one thing the browse row
-- (ItemKeyInfo.itemName) and the hovered tooltip (its title line) agree on; the
-- itemSuffix number never appears in the tooltip's link. itemID disambiguates the few
-- vanilla greens that share a name across different base items (owner 2026-11-22).
-- nil when no name is known yet (the row's ItemKeyInfo has not loaded).
function CaptureKey(ref, nameOverride)
	local name = nameOverride or (ref and ref.itemName)
	if not ref or not ref.itemID or not name or name == "" then return nil end
	return tostring(ref.itemID) .. ":" .. tostring(ref.itemLevel or 0) .. ":" .. name
end
AuctionScore.CaptureKey = CaptureKey

-- Stats of the listing, plus whether they are an ESTIMATE (base item standing in for an
-- unresolved suffix). nil = item data not loaded yet.
--   link                     -> that item exactly
--   suffixed, captured       -> the captured stats (exact)
--   suffixed, not captured   -> the bare base item (estimate)
--   unsuffixed, itemLevel>0  -> the keyed data tooltip (exact; the client resolves non-random keys)
--   otherwise                -> the bare itemID link
local function ListingStats(itemID, itemLevel, itemSuffix, link, itemName)
	if link then return Rewards.WornItemStats(link), false end
	local suffixed = (itemSuffix or 0) ~= 0
	if suffixed then
		local hit = Captured()[CaptureKey({ itemID = itemID, itemLevel = itemLevel, itemName = itemName })]
		if hit then return hit, false end
	elseif (itemLevel or 0) ~= 0 then
		local data = NS.Call("C_TooltipInfo.GetItemKey", itemID, itemLevel, 0)
		local stats = data and Rewards.StatsFromTooltipData(data)
		if stats and not AuctionScore.IsGroupSummary(data) then return stats, false end
	end
	local _, infoLink = NS.Call("C_Item.GetItemInfo", itemID)
	infoLink = NS.SafeString(infoLink)
	if not infoLink then return nil end -- not loaded yet
	return Rewards.WornItemStats(infoLink), suffixed
end

-- The itemKey tooltip of a browse GROUP (unresolved suffix) ends with
-- AUCTION_HOUSE_TOOLTIP_ITEM_KEY_GROUP ("Items in this group may vary in stats and
-- appearance..."). Matching on the global string keeps this locale-safe.
function AuctionScore.IsGroupSummary(data)
	local footer = _G.AUCTION_HOUSE_TOOLTIP_ITEM_KEY_GROUP or _G.AUCTION_HOUSE_ITEM_KEY_GROUP_TOOLTIP
	for _, line in ipairs(type(data) == "table" and data.lines or {}) do
		local text = NS.SafeString(line.leftText)
		if text and ((footer and text == footer) or text:find("may vary in stats", 1, true)) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Capture: learn suffixed stats from any item tooltip the player opens.
--
-- The hovered tooltip's hyperlink does NOT carry the browse key's itemSuffix. On
-- Forever 1.60.1 the roll is encoded as a bonus ID (item:4570::::::::12:1489:::1:12744)
-- - field 7 (suffix) is empty and field 15 is a per-variant bonus ID that is NOT the
-- 143xx suffix the browse list keys on (verified 2026-11-22, every Birchwood Maul "of X").
-- So the link cannot be matched back to a row by parsing. Instead the ROW is matched:
-- Decorate parked itemRef on every painted cell, and the cell under the mouse when the
-- tooltip fires IS the listing being described. Its browse key gets the tooltip's stats.
--------------------------------------------------------------------------------

-- The live, suffixed browse cell the mouse is over, or nil.
local function HoveredSuffixedCell()
	for cell in pairs(liveCells) do
		local ref = cell.qamScoreRef
		if ref and not ref.link and (ref.itemSuffix or 0) ~= 0 and cell:IsVisible() then
			-- the mouse is over the row (cell's parent line) or the cell itself
			local row = cell:GetParent()
			if cell:IsMouseOver() or (row and row.IsMouseOver and row:IsMouseOver()) then return cell, ref end
		end
	end
	return nil
end

-- Called for every item tooltip. Learns the hovered suffixed row's stats; returns the key.
function AuctionScore.CaptureFromLink(link, tooltipData)
	link = NS.SafeString(link)
	if not link then return nil end
	local cell, ref = HoveredSuffixedCell()
	if not cell then return nil end
	-- Guard: the tooltip must be describing the same base item as the row.
	local linkItemID = NS.SafeNumber(NS.Call("C_Item.GetItemInfoInstant", link))
	if linkItemID ~= ref.itemID then return nil end
	-- The tooltip's own title is the suffixed display name; it must agree with the row's.
	local tipName = type(tooltipData) == "table" and type(tooltipData.lines) == "table" and tooltipData.lines[1]
		and NS.SafeString(tooltipData.lines[1].leftText) or nil
	if tipName and ref.itemName and tipName ~= ref.itemName then return nil end
	local key = CaptureKey(ref, tipName)
	if not key then return nil end
	-- The tooltip that is open has the suffix lines; parse it first, API second.
	local stats = (type(tooltipData) == "table" and Rewards.StatsFromTooltipData(tooltipData)) or Rewards.WornItemStats(link)
	if not stats or AuctionScore.IsGroupSummary(tooltipData) then return nil end
	-- Durable: already known and identical -> nothing to do. Different (the client
	-- changed the roll, or a stale earlier read) -> the tooltip wins.
	local known = Captured()[key]
	if known and SameStats(known, stats) then return nil end
	Captured()[key] = stats
	cache[Key(ref.itemID, ref.itemLevel, ref.itemSuffix)] = nil -- any score built on the old stats is stale
	AuctionScore.RepaintKey(key)
	return key
end

-- The capture table lives in the account SavedVariables (NS.db.suffixStats) so a
-- listing swiped once shows its exact score on every later search and session.
function Captured()
	if NS.db then
		NS.db.suffixStats = NS.db.suffixStats or {}
		return NS.db.suffixStats
	end
	return captured -- before InitDB (tests): session-only
end

function SameStats(a, b)
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k, v in pairs(b) do if a[k] ~= v then return false end end
	return true
end

-- Re-Decorate every live cell that shows `key`.
function AuctionScore.RepaintKey(key)
	for cell in pairs(liveCells) do
		local ref = cell.qamScoreRef
		if ref and cell:IsShown() and CaptureKey(ref) == key then
			AuctionScore.Decorate(cell, cell.qamScoreText, ref, cell.qamScoreNeighbour)
		end
	end
end

function AuctionScore.CapturedCount()
	local n = 0
	for _ in pairs(Captured()) do n = n + 1 end
	return n
end

local function OnAnyItemTooltip(tooltip, data)
	if not NS.loaded or not NS.db.settings.ahScore then return end
	local link = type(data) == "table" and NS.SafeString(data.hyperlink) or nil
	if not link and tooltip and type(tooltip.GetItem) == "function" then
		local _, itemLink = tooltip:GetItem()
		link = NS.SafeString(itemLink)
	end
	if not link then return end
	local ok, err = pcall(AuctionScore.CaptureFromLink, link, data)
	if not ok then NS.WarnOnce("ahscore-capture", tostring(err)) end
end

function AuctionScore.InstallCapture()
	if AuctionScore.captureInstalled then return end
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnAnyItemTooltip)
		AuctionScore.captureInstalled = true
	end
end

function AuctionScore.Score(itemID, itemLevel, itemSuffix, link, itemName)
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
	local stats, estimate = ListingStats(itemID, itemLevel, itemSuffix, link, itemName)
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
	local result = { wearable = true, value = value, wornValue = worn.value or 0, estimate = estimate or nil }
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

-- Show the bubble with `label` and push the text(s) left of it. estimate = true
-- paints it yellow: the number is the base item's, the suffix stats are not known
-- until the row is hovered.
function AuctionScore.Place(cell, text, label, neighbour, estimate)
	local bubble = cell.qamScoreBubble
	if not bubble then
		bubble = CreateBubble(cell)
		cell.qamScoreBubble = bubble
	end
	local palette = estimate and AuctionScore.ESTIMATE or AuctionScore.EXACT
	bubble.text:SetTextColor(unpack(palette.text))
	if bubble.SetBackdropColor then
		bubble:SetBackdropColor(unpack(palette.bg))
		bubble:SetBackdropBorderColor(unpack(palette.border))
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
-- The cell remembers what it shows (qamScoreRef/Text/Neighbour) so a later hover
-- capture can repaint it in place.
function AuctionScore.Decorate(cell, text, itemRef, neighbour)
	cell.qamScoreRef, cell.qamScoreText, cell.qamScoreNeighbour = itemRef, text, neighbour
	liveCells[cell] = true
	if not NS.loaded or not NS.db.settings.ahScore then
		AuctionScore.Clear(cell, text, neighbour)
		return false
	end
	local ok, result = pcall(AuctionScore.Score, itemRef.itemID, itemRef.itemLevel, itemRef.itemSuffix, itemRef.link, itemRef.itemName)
	if not ok then
		NS.WarnOnce("ahscore", tostring(result))
		AuctionScore.Clear(cell, text, neighbour)
		return false
	end
	local label = result and AuctionScore.Format(result.gain) or nil
	if label then
		AuctionScore.Place(cell, text, label, neighbour, result.estimate)
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
	NS.Print("  AuctionScore capture: %s, %d suffixed listing(s) learned this session", AuctionScore.captureInstalled and "hooked" or "not hooked", AuctionScore.CapturedCount())
	NS.Print("  AuctionScore profile switcher: %s", AuctionScore.switcherAnchor or "not placed")
end

NS.RegisterEvent("PLAYER_LOGIN", function() AuctionScore.InstallReady(nil); AuctionScore.InstallCapture() end)
NS.RegisterEvent("ADDON_LOADED", function(name) if NS.loaded then AuctionScore.InstallReady(name) end end)
for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
	NS.RegisterEvent(event, AuctionScore.Invalidate)
end