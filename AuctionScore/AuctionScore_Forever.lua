-- Quest Automator: AH score bubbles for WoW Forever's auction house
-- (Blizzard_AuctionHouseUI, the Mainline TableBuilder list).
--
-- The name column of the Browse results, and of the per-item list behind a browse
-- row, is an AuctionHouseTableCellItemDisplayMixin cell:
--   cell.Icon       item icon (LEFT)
--   cell.Text       item name, anchored LEFT of Icon and RIGHT of the cell
--   cell.ExtraInfo  right-aligned text Blizzard shows only when Text truncates
-- Blizzard repaints a visible cell through UpdateDisplay(itemKey, itemKeyInfo)
-- (Populate -> TryUpdateDisplay -> UpdateDisplay, again on ITEM_KEY_ITEM_INFO_RECEIVED).
-- hooksecurefunc on the MIXIN catches every cell ever created from the template,
-- so no frame pool walking is needed. UpdateDisplay re-anchors Text's RIGHT each
-- time, which is why the hook runs after it and re-applies the bubble layout.
--
-- Row identity: rowData.itemKey = { itemID, itemLevel, itemSuffix, battlePetSpeciesID }
-- (AuctionHouseDocumentation.lua) - the exact listing, suffix included.
local ADDON, NS = ...
local AuctionScore = NS.AuctionScore

local provider = { name = "forever", addon = "Blizzard_AuctionHouseUI" }

function provider.IsAvailable()
	return type(AuctionHouseTableCellItemDisplayMixin) == "table"
		and type(AuctionHouseTableCellItemDisplayMixin.UpdateDisplay) == "function"
		and type(hooksecurefunc) == "function"
end

local function Paint(cell, itemKey, itemKeyInfo)
	if not itemKey or (itemKey.battlePetSpeciesID or 0) ~= 0 then
		AuctionScore.Clear(cell, cell.Text, cell.ExtraInfo)
		return
	end
	-- itemName is the suffixed display name ("Medicine Staff of Power"); the capture
	-- table is keyed on it because the hovered tooltip link does not carry the suffix.
	local result = AuctionScore.Decorate(cell, cell.Text, {
		itemID = itemKey.itemID, itemLevel = itemKey.itemLevel, itemSuffix = itemKey.itemSuffix,
		itemName = itemKeyInfo and itemKeyInfo.itemName or nil,
	}, cell.ExtraInfo)
	-- nil = item data still loading: ask again when it arrives (once per cell).
	if result == nil and not cell.qamScorePending then
		cell.qamScorePending = true
		cell:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	elseif result ~= nil and cell.qamScorePending then
		cell.qamScorePending = nil
		cell:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	end
end

function provider.Install()
	-- Stat-profile bubble centred on the BOTTOM border of the Browse results list
	-- (owner 2026-11-22: left of the search box collided with the category buttons).
	-- The results frame path is not in our Blizzard reference extracts, so it is looked
	-- up from a candidate list rather than assumed; the first that resolves wins and
	-- /qam debug names it. Blizzard's layout is not moved - the bubble straddles the edge.
	local function FindResultsList()
		local ah = AuctionHouseFrame
		if not ah then return nil end
		local browse = ah.BrowseResultsFrame
		local candidates = {
			{ "BrowseResultsFrame.ItemList.ScrollBox", browse and browse.ItemList and browse.ItemList.ScrollBox },
			{ "BrowseResultsFrame.ItemList", browse and browse.ItemList },
			{ "BrowseResultsFrame", browse },
		}
		for _, c in ipairs(candidates) do
			local f = c[2]
			if type(f) == "table" and f.GetObjectType then return f, c[1] end
		end
		return nil
	end
	local function PlaceSwitcher()
		if not NS.ProfileSwitch then return end
		local list, which = FindResultsList()
		if not list then AuctionScore.switcherAnchor = "results list not found"; return end
		if not AuctionScore.switcher then
			-- Parent to the AH frame itself so the bubble is never clipped by the list's
			-- scroll region; it only ANCHORS to the list.
			AuctionScore.switcher = NS.ProfileSwitch.Create(AuctionHouseFrame, "bubble")
			AuctionScore.switcher:SetFrameLevel((list:GetFrameLevel() or 0) + 5)
		end
		AuctionScore.switcher:ClearAllPoints()
		-- Centred on the drawn bottom border, which sits about 1.2 bubble-heights below
		-- the list frame's own bottom edge (owner 2026-11-22, measured on Forever).
		local drop = math.floor(NS.ProfileSwitch.BUBBLE_HEIGHT * 1.2 + 0.5)
		AuctionScore.switcher:SetPoint("CENTER", list, "BOTTOM", 0, -drop)
		AuctionScore.switcherAnchor = "bottom centre of " .. which
		AuctionScore.switcher:Update()
	end
	if AuctionHouseFrame and AuctionHouseFrame.HookScript then AuctionHouseFrame:HookScript("OnShow", PlaceSwitcher) end
	PlaceSwitcher()
	hooksecurefunc(AuctionHouseTableCellItemDisplayMixin, "UpdateDisplay", function(cell, itemKey, itemKeyInfo)
		Paint(cell, itemKey, itemKeyInfo)
	end)
	-- A cell that showed a bubble and is now blanked (ClearDisplay) must lose it too.
	hooksecurefunc(AuctionHouseTableCellItemDisplayMixin, "ClearDisplay", function(cell)
		AuctionScore.Clear(cell, cell.Text, cell.ExtraInfo)
	end)
	-- Blizzard's own OnEvent handles ITEM_KEY_ITEM_INFO_RECEIVED; GET_ITEM_INFO_RECEIVED
	-- (ours) falls through it untouched, so repaint from a post-hook.
	hooksecurefunc(AuctionHouseTableCellItemDisplayMixin, "OnEvent", function(cell, event, itemID)
		if event == "GET_ITEM_INFO_RECEIVED" and cell.qamScorePending and cell.rowData and cell.rowData.itemKey
			and cell.rowData.itemKey.itemID == itemID then
			local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(cell.rowData.itemKey) or nil
			Paint(cell, cell.rowData.itemKey, info)
		end
	end)
	return true
end

AuctionScore.Register(provider)