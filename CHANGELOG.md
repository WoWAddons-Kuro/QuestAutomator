# Changelog

## Unreleased

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

## Upstream 0.3.0 (Smart Quest Automation)

- Last upstream version this fork is based on.