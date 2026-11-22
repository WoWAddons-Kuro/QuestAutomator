# Restored runtime + retained UI: minimal in-game test baseline

Current pre-pick model and resolver contract: [TURN_IN_RESOLVER.md](TURN_IN_RESOLVER.md).

## Narrow correction after live baseline testing
For Rude Awakening (363), the owner observed gossip isComplete=false, log objective-completion=nil,
but global IsQuestComplete(363)=true, with an enabled Complete Quest button at the NPC.
Auto.ActGossip now accepts the original flag OR NS.Call("IsQuestComplete", questID).
This is one condition change, not a client-adapter refactor. Missing/false/nil fallback results do not
select an incomplete quest. All original eligibility/safety checks and hand-in code remain unchanged.
The mock regression failed before the edit and passes through gossip selection to GetQuestReward(0)
afterwards. Twelve cases cover completion, absent API, short-circuiting, and existing safeguards.
The owner subsequently confirmed successful automatic turn-in in the live client.

## Owner's scope
- Restore runtime by copying SmartQuestAutomation_forkbase.zip, not by reverting to the broken refactor.
- Keep pre-picker at UI/Prepick.lua and the cleaned-up settings canvas.
- Do not refactor or replace the original quest-dialog/reward policy.
- Unsupported options may store state, but must be clearly marked non-functional.

## Implementation boundary
- Rules.lua, Glow.lua, XPBar.lua: source ZIP logic, mechanical names only.
- Rewards.lua: original algorithms intact, with one description-only branch for the pre-pick reason.
- Automation.lua: source ZIP logic plus the one-condition gossip completion fallback and an isolated
  Auto.Choose boundary to TurnInResolver.Resolve (submit/manual/wait). See TURN_IN_RESOLVER.md.
- TurnInResolver.lua: preserves original 0/1 behaviour; valid multi-choice pre-picks take precedence, otherwise original rules apply.
- Core.lua: mechanical names, plus /qam pick, /qam prepick and compartment UI entry points/help.
- No Client.lua, Engine.lua, NS.Client or NS.Engine. No wrappers or overrides of Auto functions.
- UI/State.lua owns extra defaults; PrePickModel owns selections and clears them on success/abandon.
- UI/PrepickData.lua reads log/item facts solely for UI presentation; it calls original Gather and
  the shared TurnInResolver for selection display. No UI data API is injected into automation.
  Its Classic log snapshot selects a log index, reads, then immediately restores the previous index.
  Those APIs are not substituted into original runtime code.
- UI/Prepick.lua retains icons, tooltips, comparison grid, preview/unlock/position and quest list.
- Settings.lua retains canvas/sections/widgets; original working reward controls appear separately from placeholders.
- Minimap: hover lists choice-bearing quests; left-click toggles picker, right-click opens settings.

## State and terminology
| Symbol / term | Meaning and scope |
|---|---|
| questID | Stable quest identity, not the position in the quest log |
| questLogIndex | Temporary log row index, used only while reading Classic UI data |
| rewardChoiceIndex | Position in one quest's choice list; not an item ID |
| itemID | Stable item identity stored in a pre-pick |
| pending quest (UI) | Quest currently in log with at least two item reward choices, even if original policy auto-picks |
| pending item data | Not cached yet; UI retries up to six times, and closed/replaced requests are cancelled |
| prePicks[questID] | ItemID preference owned by PrePickModel; resolver matches it against the current offer |
| tier1Action..tier5Action | **Live since 2026-11-20.** Values `ask` / `upgrade` / `cash` (see QuestAutomator_SPEC §6.0); `tier3Action` is saved but unused |
| ilvlBand / valueSource | Saved-only placeholders, no effect. (`upgradeBand` = the live "upgrade threshold" slider, default 5%; `weaponProficiency` is live) |
| rewardMode / weapons / trinkets / fallbackToValue / manualQuality | Original, functional reward policy settings |
| prePickUI | Functional UI-only on-accept display toggle, not a hand-in override |
| prePickUnlocked / prePickPos | Functional UI preview/movement and account-wide saved position |

No undefined critical terms remain for this integration. Future gameplay eligibility APIs require a
separate design and verified client semantics, not guesses based on similarly named fields.

## Tests (from workspace root)
```powershell
python QuestAutomator/tests/check_restored_runtime.py
Get-ChildItem QuestAutomator -Recurse -Filter *.lua | ForEach-Object { luac5.1 -p $_.FullName }
lua5.1 QuestAutomator/tests/ui_smoke.lua era
lua5.1 QuestAutomator/tests/turn_in_resolver.lua
lua5.1 QuestAutomator/tests/ui_smoke.lua forever
lua5.1 QuestAutomator/tests/ui_smoke.lua era zhCN
lua5.1 QuestAutomator/tests/ui_smoke.lua forever zhCN
```
The smoke suite uses mocked WoW APIs and frame methods; it is not a real-client compatibility certification.
It exercises TOC load, settings creation/update, original and UI defaults, independent quest picks,
selection restoration (including index 0), tooltips, minimap click semantics, sample preview, item-data
retry cancellation, empty UI, placeholder inertness, and the original zero-choice reward/accept paths.

## Owner's publish/reload checklist
Publishing and releasing are owner-only. No game files were modified by this work.
1. Use cmd/publish.cmd to install QuestAutomator, then /reload. /qam debug should show version v2026.11.18.1709.
2. Right-click minimap -> settings. Check layout, scroll height, labels, original reward controls.
3. Toggle a tier/proficiency/value placeholder: it says Not implemented — no effect; /qam status still
   reports the original reward mode. Placeholder changes must not alter the original choice policy.
4. Unlock preview: real items load, hover shows tooltips, drag and relock; /reload preserves position.
5. Left-click minimap with no choice-bearing quests: window opens with empty message; automation stays unchanged.
6. With two choice-bearing quests: hover lists both; click opens picker; clicking each quest changes rewards.
   Picks remain stored for both quests and say your pick. Close/reopen and /reload retain them.
7. Accept a quest whose original policy leaves reward choice manual: on-accept picker appears if enabled.
8. Test original NPC quest acceptance and a zero-choice turn-in, including Rude Awakening if available.
   Record whether it stops at gossip, progress, or Complete Quest; paste /qam log 20 after a failure.
9. Select a non-default reward before hand-in, then verify the actual received item. A valid pre-pick overrides the original recommendation, not controller safeguards.
10. Repeat the relevant checks on Forever and Classic Era; note client build and enabled addons.

## Outstanding / intentionally not promised
- In-game appearance and both clients' live behaviour are not verified by mocks.
- Other original runtime client/API limitations remain. The IsQuestComplete gossip fallback was
  confirmed working by the owner, as was the pass-through resolver turn-in checkpoint. Pre-pick
  consumption is now locally tested and awaits verification of the actual received item in game.
- Current list layout grows with quest count (no virtualized/scrolling quest list yet).
- No tier engine, new weapon eligibility policy, or auction/disenchant providers. NPC glow still uses original scoring.
- Do not mark the historical port/tier spec complete based on this UI-only test baseline.