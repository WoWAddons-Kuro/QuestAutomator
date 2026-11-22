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
	-- Stat-profile bubble left of the Browse search box (SPECS/STAT_PROFILES.md). The
	-- search box frame path is not in our Blizzard reference extracts, so it is looked up
	-- from a short candidate list rather than assumed; when none resolves the bubble is
	-- skipped and /qam debug says so. Anchored RIGHT -> search box LEFT; Blizzard's layout
	-- is not moved.
	local function FindSearchBox()
		local ah = AuctionHouseFrame
		if not ah then return nil end
		local candidates = {
			ah.SearchBar and ah.SearchBar.SearchBox,
			ah.BrowseResultsFrame and ah.BrowseResultsFrame.SearchBar and ah.BrowseResultsFrame.SearchBar.SearchBox,
			ah.SearchBox,
			_G.AuctionHouseFrameSearchBox,
		}
		for _, f in ipairs(candidates) do
			if type(f) == "table" and f.GetObjectType then return f end
		end
		return nil
	end
	local function PlaceSwitcher()
		if not NS.ProfileSwitch then return end
		local box = FindSearchBox()
		if not box then AuctionScore.switcherAnchor = "search box not found"; return end
		if not AuctionScore.switcher then
			AuctionScore.switcher = NS.ProfileSwitch.Create(box:GetParent(), "bubble")
		end
		AuctionScore.switcher:ClearAllPoints()
		AuctionScore.switcher:SetPoint("RIGHT", box, "LEFT", -AuctionScore.BUBBLE_GAP - 4, 0)
		AuctionScore.switcherAnchor = "left of search box"
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