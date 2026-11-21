-- Quest Automator: AH score bubbles for the Classic Era auction house
-- (Blizzard_AuctionUI: AuctionFrameBrowse with BrowseButton1..N rows and a
-- FauxScrollFrame; rows are repainted by AuctionFrameBrowse_Update and the item
-- comes from GetAuctionItemLink("list", offset + i)).
--
-- NOT IMPLEMENTED YET. The provider registers so /qam debug lists it, and
-- IsAvailable() returns false until the hook is written. When it is, the shape is:
--   hooksecurefunc("AuctionFrameBrowse_Update", function()
--     for i = 1, NUM_BROWSE_TO_DISPLAY do
--       local button, name = _G["BrowseButton" .. i], _G["BrowseButton" .. i .. "Name"]
--       local link = GetAuctionItemLink("list", FauxScrollFrame_GetOffset(BrowseScrollFrame) + i)
--       AuctionScore.Decorate(button, name, { link = link })
--     end
--   end)
local ADDON, NS = ...
local AuctionScore = NS.AuctionScore

local provider = { name = "classic_era", addon = "Blizzard_AuctionUI" }

function provider.IsAvailable()
	return false
end

function provider.Install()
	return false
end

AuctionScore.Register(provider)