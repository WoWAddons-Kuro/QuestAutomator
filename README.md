# QuestAutomator

Accepts and hands in quests for you and picks the reward, so questing is one click less per NPC.
Fork of **Smart Quest Automation 0.3.0** by qqytqqyt, renamed so it can coexist with the original, and
extended to run on **WoW Forever** and **Classic Era / Anniversary / Hardcore** from one TOC.

Slash command: **`/qam`** (also `/questautomator`). Settings: Esc → Options → AddOns → QuestAutomator.

## What it does

- Talking to an NPC: hands in completed quests first, then takes the quests offered (low-level, repeatable
  and PvP-flagging quests are skipped by default; quests that cost money are always left to you).
- Reward panel with several choices: picks one by the priority rules below, or leaves the window open and
  **glows** the reward it would take so you can decide.
- Hold **Shift** (configurable) while talking to an NPC to do that whole conversation by hand.
- `/qam ignore npc` / `/qam ignore quest` keep specific NPCs or quests manual forever.
- Minimap button (left-click toggles, right-click menu), optional experience-bar overlay showing the XP
  of completed quests not yet handed in.

## Reward choice

Rewards are evaluated in order; the first tier that applies decides whether the addon picks automatically
or only recommends (glow + chat line). Every tier's action is a setting.

| Tier | When | Default |
|---|---|---|
| Quality | a reward of Rare quality or better is offered | recommend |
| 1 | a trinket, relic, Use/proc item or non-equipment is offered (hard to value) | recommend |
| 2 | one wearable reward is a clear upgrade over what you wear in that slot | auto |
| 3 | one wearable reward is a sidegrade (within a few item levels) | auto |
| 4 | two or more rewards are upgrades or sidegrades | recommend |
| 5 | nothing wearable: the most valuable reward | auto |

“Wearable” means your class's *best* armour class at your level (mail until 40 then plate for warriors and
paladins, etc.) and weapons your class can train. `/qam why` explains the choice on screen.

## Commands

`/qam` prints status; `/qam help` lists everything. Highlights: `on|off`, `pause`, `tier <1-5> recommend|auto`,
`quality <1-5|off>`, `modifier shift|ctrl|alt|none`, `stats <stat>...`, `ignore`, `why`, `log`, `settings`, `debug`.

## Clients

| Flavour | Interface | Status |
|---|---|---|
| WoW Forever | 16001 | primary, tested |
| Classic Era / Anniversary / Hardcore | 11509 | in progress |

## Development

Part of the `3P_WoWAddons` workspace: `cmd\publish.cmd` installs into the game, `cmd\release.cmd` tags
(`vYYYY.MM.DD.HHMM`). See `..\QuestAutomator_SPEC.md` for the design and roadmap.

## Credits and license

Original addon: Smart Quest Automation by **qqytqqyt** (https://github.com/qqytqqyt/SmartQuestAutomation).
The upstream repository was unreachable (404) when this fork was made (2026-11-17) and the 0.3.0 release
shipped **no license file**; the original author's rights are reserved. Until a license is confirmed this
fork is published for personal use with full attribution. Fork changes © Kuro.