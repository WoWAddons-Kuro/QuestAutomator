# Changelog

## Unreleased

### Pre-pick consumption checkpoint (v2026.11.18.1709, in-game test pending)
- Owner confirmed the previous resolver checkpoint turns quests in successfully.
- Loaded PrePickModel; the picker delegates storage, validation and lifecycle cleanup to it.
- Resolver matches saved item IDs to current offered indices, waits for unloaded data, and falls
  back to original rules for absent/ambiguous rewards. No changes to Automation.lua or Glow.lua.
- Picker and minimap show your pick/loading/unavailable states; removed active saved-only messages.
- Original Rewards scoring remains unchanged; Describe now labels selected rewards as your pre-pick.
- Added reordered-hand-in, selection-change-on-retry, five-return Era item info, and cleanup tests.

### Turn-in resolver checkpoint (in-game test pending)
- Extracted submit/manual/wait decisions into TurnInResolver.lua; only Auto.Choose calls it so far.
- Preserves original 0/1/multiple reward choice behaviour and all existing controller safeguards.
- Malformed/failed resolver responses leave the dialog manual; no automatic fallback on errors.
- Pre-picks, model migration and glow integration remain deferred until the owner tests this checkpoint.
- Minimap left-click now toggles the pre-picker open/closed; right-click still opens settings.

### Restored runtime / minimal UI test baseline
- Copied original runtime from SmartQuestAutomation_forkbase.zip; deleted Client.lua and Engine.lua.
- Reward scoring, rules, glow and XP code retain ZIP logic, with mechanical naming only.
- Automation has one targeted correction: when gossip says incomplete, query IsQuestComplete(questID).
  Live dumps confirmed this distinction for Rude Awakening. Mock regression and safety checks pass.
- Kept the cleaned settings layout and UI/Prepick.lua. Original reward mode, weapon/trinket,
  fallback and quality controls work; tier/sidegrade/proficiency/value-source controls are marked
  **Not implemented — no effect** and store state only.
- Pre-picker supports real-item preview, quest browsing and stored selections. Stored picks are
  explicitly **not applied at hand-in**; they cannot change the restored reward policy.
- Minimap left-click opens the pre-picker (including an empty state); right-click opens settings.
- Added Lua 5.1 mock smoke tests and exact comparison with the source ZIP. In-game testing pending.

## Earlier refactor (removed; historical notes below)

### Fork
- Forked Smart Quest Automation 0.3.0 (qqytqqyt) as **QuestAutomator**. Every global renamed so both can
  be installed: `QuestAutomatorDB` / `QuestAutomatorCharDB`, slash `/qam` and `/questautomator`,
  settings variables `QAM_*`, minimap frame `QuestAutomatorMinimapButton`, addon-compartment functions.
- TOC targets WoW Forever (16001) and Classic Era (11509) from one file.

### Classic Era
- New `Client.lua`: one adapter table per flavour (`forever`, `classic_era`) for every API whose shape
  differs - quest title / trivial / repeatable by ID, quest-log walk and reward XP, greeting rows,
  item stats, talent trees, reward-panel hooks and buttons (Era's quest log draws through
  `QuestFrameItems_Update` / `QuestLogItemN`), quest-log choice functions, tooltip stat strings.
- Era tooltip stat strings ("Improves your chance to hit by %s%%", "+%s Defense"...) parsed; `%%` literal.
- Hunter Survival detection from `C_SpecializationInfo.GetSpecializationInfo` tabs on Era.

### Reward priority engine (replaces fit / value / manual)
- Tiers, first match wins: **Q** rare or better -> recommend; **1** hard to value (trinket, relic, Use or
  proc effect, not equipment) -> recommend; **2** one wearable reward is a clear upgrade -> auto;
  **3** one wearable reward is a sidegrade -> auto; **4** two or more upgrades/sidegrades -> recommend;
  **5** nothing wearable: most valuable -> auto. Every tier's action is a setting.
- "Upgrade" compares the reward's item level with the weakest piece you wear in that slot
  (`ilvlBand`, default 2). "Wearable" is your class's best armour class at its level (lighter
  armour does not count) and weapons your class can learn (or has trained: `weaponProficiency`).
- The glow marks the engine's pick in both auto and recommend. `/qam why` lists each reward's
  item level vs worn, wearable / not and why, value and tie-break score.
- Value source setting (`vendor` now; `auction` / `disenchant` accept a provider via
  `QuestAutomator.Client.RegisterValueProvider`).
- Settings page rebuilt (Esc -> Options -> AddOns -> QuestAutomator): five tier dropdowns, sidegrade band,
  wearable weapons, value source, ask-on-accept, read-only class stat weights.
- Removed settings `rewardMode`, `weapons`, `trinkets`, `fallbackToValue` (migrated away on load).

### Pre-pick window
- When an accepted quest's reward would only be recommended, a small window lists the choices with
  the engine's suggestion glowing; click one and the hand-in becomes automatic. Stored per character
  by quest and item ID; cleared on hand-in or abandon. `/qam pick [questID]`, `/qam prepick on|off`.
- Several quests with a choice at once: the window lists every log quest that has one (your pick /
  auto / decide); click a quest to see its rewards. Handing in or abandoning the shown quest moves on
  to the next. The minimap tooltip lists the same quests; left-click opens the window while any exist
  (otherwise it toggles the automation, as before).
- Quest-log rewards are read by item ID, not by log index, so the window shows the right items no
  matter which quest is selected in the log (Era selects and restores the log entry).

## Upstream 0.3.0 (Smart Quest Automation)

- Last upstream version this fork is based on.