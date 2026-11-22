# Stat profiles (`Rules.lua`, `UI/StatWeights.lua`)

Owner design 2026-11-22. Replaces the single-row-per-class stat weights and the per-cell
account overrides (`NS.db.statWeights[class][key]`).

## Why

A class is not one set of stat values. A leveling shaman wants Strength and Agility; a Resto
shaman wants Intellect and healing; the one `Rules.WEIGHTS.SHAMAN` row served both and was a
caster profile with weapon DPS weighted for melee (fixed as a band-aid in `1ba047f`). Druid and
Paladin have the same split. The player, not a talent heuristic, knows which one they are.

## The model

- A **profile** is a named, complete stat-weight row for one class: `{ STRENGTH = 1.0, ... }` plus
  the weapon pseudo-stats (`MELEE_DPS`, `MELEE_SPEED`, `RANGED_DPS`, `RANGED_SPEED`).
- Each class ships **built-in profiles**. The first is the leveling default. Built-ins are code,
  never edited in place.
- The player can create **custom profiles**. A custom profile is a full copy of the profile it
  was forked from, with the player's edits applied, and a player-editable name.
- Custom profiles are **account-wide**: every character of that class sees them.
- The **selection** - which profile this character uses - is **per character**.

### Built-in profiles (first = leveling default)

| Class | Profiles |
|---|---|
| WARRIOR | Arms/Fury Leveling, Protection |
| PALADIN | Retribution Leveling, Holy, Protection |
| HUNTER | Marksman/Beast Leveling, Survival |
| ROGUE | Combat Leveling, Subtlety |
| PRIEST | Shadow Leveling, Holy/Discipline |
| SHAMAN | **Balanced Leveling**, Enhancement, Elemental, Restoration |
| MAGE | Frost Leveling, Fire, Arcane |
| WARLOCK | Affliction/Demonology Leveling, Destruction |
| DRUID | Feral Leveling, Balance, Restoration |

Names are display strings; the stable identity is a `QuestAutomator_StatProfileID` (see Types).
The *Leveling* row of each class is today's `Rules.WEIGHTS[class]` (corrected where it was
wrong - shaman is done; Druid and Paladin to be reviewed in the same commit). The other rows are
new and need owner review before they ship; they are listed as TBD below.

### Selector UI (Stat values section, `UI/StatWeights.lua`)

A radio group above the grid, one button per profile available to this class:

```
( ) Shaman Balanced Leveling
( ) Shaman Enhancement
( ) Shaman Elemental
( ) Shaman Restoration
( ) Custom: Shaman Enhancement        [ edit name ]
```

- Selecting a radio switches this character's profile and refreshes the grid.
- The grid shows the **selected** profile's values. Built-in cells show the value; custom cells
  show the value with the forked-from default greyed behind it, as the grid does today.
- **Editing any cell of a built-in profile forks it**: a new custom profile named
  `Custom: <built-in name>` is created with that edit applied, its radio appears, and this
  character is switched to it. The built-in itself is untouched.
- Editing a cell of a custom profile edits that profile in place (all characters on it see the
  change - it is one shared row).
- `[ edit name ]` next to a custom radio renames it (an inline edit box; Enter commits, Escape
  cancels). Names must be non-empty and unique within the class.
- A custom profile gets a `[ delete ]` too. Deleting one that other characters have selected
  falls those characters back to the class leveling default on their next load.
- **Reset to class defaults** becomes **Reset this profile**: on a custom profile, restores it to
  its forked-from built-in's values; on a built-in it is disabled (nothing to reset).

### `/qam stats`

The `/qam stats <stat>...` per-character list override (`NS.chardb.stats`, `Rules.OVERRIDE_WEIGHTS`)
is **retired**. It was a second, weaker way to say the same thing. `InitDB` drops `chardb.stats`.
`/qam stats` with no argument still prints the profile; `/qam stats <name>` selects a profile by
(case-insensitive, prefix) name; anything else prints the available profile names.

## Types (linguistic keying)

```lua
---@alias QuestAutomator_StatKey string              -- "STRENGTH" | ... | "MELEE_DPS" (Rules.STAT_KEYS + weapon pseudo-stats)
---@alias QuestAutomator_StatWeight number           -- points per stat point, >= 0
---@alias QuestAutomator_StatProfileID string        -- "SHAMAN:leveling" (built-in) | "SHAMAN:custom:3" (custom)
---@alias QuestAutomator_StatProfileName string      -- display name; player-editable for custom
---@alias QuestAutomator_ClassToken string           -- "SHAMAN"

---@class QuestAutomator_StatProfile
---@field id QuestAutomator_StatProfileID
---@field class QuestAutomator_ClassToken
---@field name QuestAutomator_StatProfileName
---@field builtin boolean                            -- true: code-defined, read-only
---@field forkedFrom QuestAutomator_StatProfileID|nil -- custom only: the built-in it copied
---@field weights table<QuestAutomator_StatKey, QuestAutomator_StatWeight>  -- COMPLETE row
```

## Storage

```lua
-- account (QuestAutomatorDB)
db.statProfiles = {                       -- custom profiles only; built-ins are never stored
  ["SHAMAN:custom:1"] = { id, class, name, builtin = false, forkedFrom = "SHAMAN:enhancement", weights = {...} },
}
db.statProfileNextID = 2                  -- monotonic, never reused

-- character (QuestAutomatorCharDB)
cdb.statProfileID = "SHAMAN:custom:1"    -- nil = the class leveling default
```

Migration (`InitDB`, one-shot, versioned by `settingsVersion`):
- If `db.statWeights[class]` has any cells: create `Custom: <class> Balanced Leveling` from the
  leveling built-in with those cells applied; characters of that class that log in with no
  `cdb.statProfileID` are pointed at it. Then `db.statWeights = nil`.
- `cdb.stats` (the `/qam stats` list) is dropped. Its weights were never a real profile.

## Rules API (replaces the per-cell functions)

```lua
Rules.BUILTIN_PROFILES[class] -> QuestAutomator_StatProfile[]      -- ordered; [1] is the leveling default
Rules.Profiles(class)          -> QuestAutomator_StatProfile[]      -- built-ins then customs, display order
Rules.Profile(id)              -> QuestAutomator_StatProfile|nil
Rules.SelectedProfile(class)   -> QuestAutomator_StatProfile        -- cdb.statProfileID, else [1]; never nil
Rules.SelectProfile(id)                                            -- sets cdb.statProfileID
Rules.ForkProfile(fromID, name?) -> QuestAutomator_StatProfile       -- new custom, full copy
Rules.SetProfileWeight(id, key, value)                             -- custom only; errors on builtin
Rules.RenameProfile(id, name)                                      -- custom only; unique per class
Rules.DeleteProfile(id)                                            -- custom only
Rules.ResetProfile(id)                                             -- custom only: weights := forkedFrom's

Rules.Weights(class) -> weights, source   -- source = "builtin" | "custom"; the selected profile's row.
                                          -- Rules.Player() is unchanged for every caller.
```

`Rules.DefaultWeight / UserWeight / EffectiveWeight / SetUserWeight / ResetUserWeights` are
removed. `Rules.ApplyClientWeightOverrides` (the Era druid-DPS override) applies to the **built-in**
rows at load, as now; a custom profile forked after that inherits the overridden value.

## What does NOT change

- `Rewards.StatValue / FitScore / Evaluate`, `Tooltip.lua`, `AuctionScore`, the pick window: all
  read `player.weights` from `Rules.Player()` and are untouched.
- Weapon pseudo-stat keys and `Rules.WeaponWeight`.
- The reward tiers.

## Profile switchers outside the settings page

The selected profile changes every score the player sees, so it must be visible and switchable
wherever scores are read, not only in Settings. Both switchers below are the SAME control -
`UI/ProfileSwitch.lua`, `NS.ProfileSwitch.Create(parent, style)` - in two visual styles. Changing
the profile from any of them calls `Rules.SelectProfile(id)` and then `NS.OnSettingsChanged()`,
which must now also: re-evaluate the open pick window (`PrePick.Refresh`), re-Decorate every live
AH cell (`AuctionScore.Invalidate()` + repaint), and refresh the stat-values grid if it is open.

### Pick window (`UI/Prepick.lua`)

A small label row under the title, before the quest list:

```
        Reward for Old Ironforge Incursion
           Pre-select your reward.
   Stat profile: Shaman Enhancement  v          <- click = popup
```

- Text is `L["Stat profile: %s"]` with the selected profile's display name, label tone.
- Click opens a popup (MenuUtil.CreateContextMenu where present, else a plain dropdown of
  our own buttons) listing `Rules.Profiles(class)` with a radio mark on the current one; picking
  one switches and the pick window re-evaluates in place, so the coin / "+N" columns update.
- Style: `"label"`.

### Auction house (`AuctionScore/AuctionScore_Forever.lua`, and each provider that has a search bar)

A **bubble** to the LEFT of the search box, drawn with the AH score bubble's own widget
(`AuctionScore.CreateBubble`-style backdrop, `EXACT` palette but at reduced alpha so it reads as
chrome, not as a score): it shows the selected profile's short name.

```
   [ Enhancement ]  [ Search .................... ]  [ Filter ] [ Search ]
```

- Clicking it opens the same popup as the pick window. On switch, every visible AH row is
  re-Decorated, so the numbers and yellow/green states refresh without re-searching.
- The displayed name is the profile name with the class word stripped when it leads
  (`"Shaman Enhancement"` -> `"Enhancement"`); custom names are shown as typed, truncated to fit.
- Anchored `RIGHT` of the search box's `LEFT` with the bubble gap; the search box is NOT moved
  (Blizzard owns its layout). If the gap left of the box is too narrow on a provider, the bubble
  anchors above-left of the box instead. Decided per provider when implemented.
- Style: `"bubble"`.
- Setting: shown whenever `settings.ahScore` is on - it is part of the same feature.

### `/qam profile`

`/qam profile` prints the current profile and lists the class's profiles; `/qam profile <name>`
selects by case-insensitive prefix. (`/qam stats` becomes an alias of this.)

## Dual-wield off-hand DPS factor (deferred; lands on the profile)

`OFFHAND_DPS_FACTOR` becomes one more key in a profile's `weights` (0..1). A 1H weapon compared
against a worn 2H (or a 2H against a worn 1H) is scaled: stats x2, DPS x (1 + factor). 0 = the
class/spec does not dual-wield, so a 1H is one weapon. Built-in defaults: Warrior/Rogue/Hunter
leveling rows ~0.45/0.55/0.35; SHAMAN Enhancement 0.45 on Era and **0 on Forever** (via
`Client_Forever.StatWeightOverrides`, same mechanism as druid DPS); everything else 0. Specced and
implemented after this profile work lands - separate commit, separate owner review of the numbers.

## Phases

- [ ] **P1 Rules**: `BUILTIN_PROFILES`, the API above, `Rules.Weights` reads the selected profile;
      `InitDB` storage + migration; `/qam stats` repointed. Pure tests for fork/edit/rename/delete/
      reset/migration (`tests/stat_profiles.lua`). Existing suites still pass.
- [ ] **P2 UI**: radio group + edit-name + delete in `UI/StatWeights.lua`; grid bound to the
      selected profile; fork-on-first-edit; `ui_smoke` coverage.
- [ ] **P2b Switchers**: `UI/ProfileSwitch.lua` (one control, two styles); pick-window label row;
      AH bubble left of the search box per provider; `OnSettingsChanged` fan-out; `/qam profile`.
- [ ] **P3 Built-in rows**: owner reviews the non-leveling rows (TBD below) and the Druid/Paladin
      leveling rows; one commit.
- [ ] **P4 Dual-wield factor** (own spec paragraph above; after P1-P3).

## Open questions / TBD

- **TBD numbers**: every non-leveling built-in row. I will propose them in P3 as a table for
  review; nothing ships unreviewed.
- Should a custom profile be selectable by a *different* class? No - profiles are per class;
  the radio only lists the current class's. (Decided: no.)
- `[ edit name ]` and `[ delete ]` placement: inline right of the radio, or a small toolbar under
  the group? Inline is assumed.
- Max custom profiles per class? None enforced; the radio group grows. Revisit if it gets silly.