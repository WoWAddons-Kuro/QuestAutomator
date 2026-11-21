-- Quest Automator: AH score bubbles inside Auctionator's result lists (its own
-- scrolling data-provider tables replace the Blizzard browse list on Era).
--
-- NOT IMPLEMENTED YET. Registers so /qam debug lists it; IsAvailable() stays
-- false until Auctionator's current row/cell API has been verified in game
-- (AuctionatorResultsListingMixin / its cell templates differ per release).
local ADDON, NS = ...
local AuctionScore = NS.AuctionScore

local provider = { name = "auctionator", addon = "Auctionator" }

function provider.IsAvailable()
	return false
end

function provider.Install()
	return false
end

AuctionScore.Register(provider)