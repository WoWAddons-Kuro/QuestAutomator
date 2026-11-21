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

local function Paint(cell, itemKey)
	if not itemKey or (itemKey.battlePetSpeciesID or 0) ~= 0 then
		AuctionScore.Clear(cell, cell.Text, cell.ExtraInfo)
		return
	end
	local result = AuctionScore.Decorate(cell, cell.Text, {
		itemID = itemKey.itemID, itemLevel = itemKey.itemLevel, itemSuffix = itemKey.itemSuffix,
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
	hooksecurefunc(AuctionHouseTableCellItemDisplayMixin, "UpdateDisplay", function(cell, itemKey)
		Paint(cell, itemKey)
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
			Paint(cell, cell.rowData.itemKey)
		end
	end)
	return true
end

AuctionScore.Register(provider)