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
- Listing identity is the auction **item key** `{ itemID, itemLevel, itemSuffix }`. A hyperlink is
  accepted instead when the UI has one (Era, Forever's per-auction item list).
- Results are cached per key; the cache is dropped on `PLAYER_EQUIPMENT_CHANGED`,
  `PLAYER_LEVEL_UP`, `SKILL_LINES_CHANGED`. Item data not loaded yet => not cached, repainted on
  `GET_ITEM_INFO_RECEIVED`.

### Random-suffix listings ("of the Monkey") - estimate, then capture (owner 2026-11-22)

From addon code the Forever client will **not** resolve a random-suffix roll for a browse key.
`C_TooltipInfo.GetItemKey(itemID, itemLevel, itemSuffix, requiredLevel)` and a scanning
`GameTooltip:SetItemKey(...)` both return the group placeholder - *"Items in this group may vary in
stats and appearance. Check the auction's tooltip before buying."* - with weapon DPS only and no stat
lines. Verified 1.60.1 (71037) for every suffix of five weapon groups; `requiredLevel` was present
and correct and changed nothing. Blizzard's own hover tooltip, from secure code, gets the full item.
(The bare-itemID hyperlink `item:ID::::::suffix` likewise resolves to the base item.)

So a suffixed row is handled in two steps:

| State | Bubble | Source |
|---|---|---|
| Not yet hovered | **yellow** `+12.4` (`AuctionScore.ESTIMATE`) | base item: DPS / armour, no suffix stats |
| Hovered once this session | **green** `+19.5` (`AuctionScore.EXACT`) | the tooltip the player opened |

Capture: `TooltipDataProcessor` post-call on every item tooltip (`AuctionScore.InstallCapture`). The
hovered tooltip's link does **not** carry the browse `itemSuffix` (on Forever the roll is a bonus ID,
field 15, e.g. `item:4570::::::::12:1489:::1:12744`), so the link cannot be matched to a row. Instead
the live suffixed browse cell **under the mouse** is the listing being described
(`HoveredSuffixedCell`; `Decorate` parks `itemRef` on every painted cell). Its stats are parsed from
the open tooltip and stored under the **durable capture key** `itemID:itemLevel:Display Name`
(`AuctionScore.CaptureKey`) - the display name ("Medicine Staff of Power") is the one thing the row
(`ItemKeyInfo.itemName`) and the tooltip title agree on; `itemID` disambiguates same-named greens
(owner 2026-11-22). The store is **account SavedVariables** `QuestAutomatorDB.suffixStats`: a listing
swiped once is exact on every later search and session. A hover whose stats differ from the stored
row overwrites it (the tooltip is the truth); identical = no-op. Every live cell with that key is
re-Decorated (`RepaintKey`). `result.estimate` carries the state to `Place`.

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
- [ ] Suffixed rows ("Medicine Staff of X") start YELLOW with the base-item gain; hovering one turns
      that row GREEN with the exact gain and the number matches the tooltip's `Quest Automator` line.
      Scroll away and back: the green value is remembered. `/qam debug` counts captures.
- [ ] Toggle the setting off: bubbles disappear on next repaint.
- [ ] `/qam debug` lists `AuctionScore forever: installed`, Era/Auctionator `not installed`.