# AH score bubbles (`AuctionScore/`)

Owner decisions 2026-11-21. Every **equipment** row in an auction-house browse list that is an
**upgrade** over what the character wears gets a small green bubble, right-justified inside the
name column, with the stat-point gain:

```
[icon] Tough Leather Gloves of the Monkey                 (+2.2)
[icon] Heavy Linen Cloak                                   (+12.2)
[icon] Bronze Axe                                                    <- not an upgrade: nothing drawn
```

## Rules

- **Number** = `Rewards.StatValue(item) - Rewards.WornItem(slot).value`, the same class-weighted
  stat points `Tooltip.lua` and the pick window show. One decimal, always signed: `+1.2`, `+12.2`.
- **Shown only when gain > 0.1** (`AuctionScore.MIN_DELTA`). Sidegrades, downgrades, unwearable
  items, non-equipment, battle pets: nothing is drawn and Blizzard's layout is untouched.
- Always on while `settings.ahScore` is true (default on; checkbox under *Pre-pick and feedback*).
- Listing identity is the auction **item key** `{ itemID, itemLevel, itemSuffix }` so "of the
  Monkey" gets its own stats (`C_TooltipInfo.GetItemKey`), not the bare itemID's. A hyperlink is
  accepted instead when the UI has one (Era).
- Results are cached per key; the cache is dropped on `PLAYER_EQUIPMENT_CHANGED`,
  `PLAYER_LEVEL_UP`, `SKILL_LINES_CHANGED`. Item data not loaded yet => not cached, repainted on
  `GET_ITEM_INFO_RECEIVED`.

## Structure

| File | Role |
|---|---|
| `AuctionScore/AuctionScore.lua` | UI-independent: `Score()`, `Format()`, the bubble widget (`Place`/`Clear`/`Decorate`), the provider registry. |
| `AuctionScore/AuctionScore_Forever.lua` | **Implemented.** `Blizzard_AuctionHouseUI` TableBuilder list: `hooksecurefunc(AuctionHouseTableCellItemDisplayMixin, "UpdateDisplay")` -> `Decorate(cell, cell.Text, itemKey, cell.ExtraInfo)`. Covers Browse results and the per-item list (same mixin). |
| `AuctionScore/AuctionScore_ClassicEra.lua` | Stub (`IsAvailable()=false`). Target: `Blizzard_AuctionUI`, `hooksecurefunc("AuctionFrameBrowse_Update")`, rows `BrowseButtonN`, link from `GetAuctionItemLink("list", i)`. |
| `AuctionScore/AuctionScore_Auctionator.lua` | Stub. Auctionator's own result listing; verify its row/cell API in game first. |

### Provider interface

```lua
{ name = "forever",                  -- /qam debug label
  addon = "Blizzard_AuctionHouseUI",  -- Install() runs once this addon is loaded (nil = at PLAYER_LOGIN)
  IsAvailable = function() -> bool,   -- the globals it hooks exist
  Install     = function() -> bool }  -- hook the UI; per painted row call
                                      --   AuctionScore.Decorate(cell, nameFontString, itemRef[, neighbourFontString])
                                      -- itemRef = { itemID, itemLevel, itemSuffix } or { link = "|Hitem:..." }
```

Providers never read item data or create widgets; they only map "this row was repainted" onto
`Decorate`/`Clear`. `AuctionScore.Register(provider)` validates the fields; `AuctionScore.InstallReady`
runs at `PLAYER_LOGIN` and on every `ADDON_LOADED` (the Blizzard AH addon is LoadOnDemand).

### Bubble layout

`Place(cell, text, label, neighbour)` anchors the bubble `RIGHT` of the cell, re-points `text`'s `RIGHT`
to the bubble's `LEFT` (saving the original anchor once per cell), and shifts `neighbour` (Forever's
`ExtraInfo`) the same way. `Clear` hides the bubble and restores the saved anchor. Blizzard's
`UpdateDisplay` resets `Text`'s RIGHT every paint, which is why the hook runs *after* it.

## In-game verification (owner)

- [ ] Forever: open AH, browse Armor; upgrades show `+N.N`, nothing on sidegrades; name truncation
      still ellipsises left of the bubble; scroll fast - no stale bubbles on recycled rows.
- [ ] `C_TooltipInfo.GetItemKey` returns stats for a suffixed listing (compare bubble vs. the
      tooltip line on hover). If it returns nothing on Forever, `ListingStats` falls back to the bare
      itemID link - note it here.
- [ ] Toggle the setting off: bubbles disappear on next repaint.
- [ ] `/qam debug` lists `AuctionScore forever: installed`, Era/Auctionator `not installed`.