# Pre-pick model and reward-selection boundary

The authoritative resolver contract is now [TURN_IN_RESOLVER.md](TURN_IN_RESOLVER.md).
The obsolete RewardSelectionPolicy.lua prototype was removed rather than retaining two policy implementations.
Supersedes the saved-only pre-pick limitation in [RESTORED_UI_BASELINE.md](RESTORED_UI_BASELINE.md).
The restored NPC controller and the live-confirmed IsQuestComplete gossip fallback remain in place.

## Decisions / scope
- Extract model/storage before extending hand-in behaviour; no broad client abstraction or MVC framework.
- Retain original Rewards.Gather and Rewards.Evaluate algorithms. Do not override or monkey-patch them.
- One explicit call in Auto.Choose invokes TurnInResolver.Resolve after TurnInAllowed.
- A valid player selection overrides reward-mode/quality/weapon recommendation gates, not NPC automation safeguards.
- No saved selection, absent reward, or ambiguous item identity -> use the original reward policy.
- While any offered item choice is unidentified/unloaded, a stored selection waits; never guess an index.
- Picks remain until actual QUEST_TURNED_IN / QUEST_REMOVED. Do not clear on attempted turn-in or UI close.
- Tier/sidegrade/proficiency/value-provider placeholders stay inert.
- UI data-reading remains isolated in UI/PrepickData.lua; do not move its APIs into the gameplay controller.

## Boundaries and files
| Component | Owns | Forbidden |
|---|---|---|
| Models/PrePickModel.lua | Saved item IDs, validation, revision, lifecycle cleanup, resolution against choice snapshots | Frames, WoW selection calls, reward scoring |
| TurnInResolver.lua | Pick precedence, explicit pending/invalid-match handling, delegation to original scoring | Quest API calls, timers, GetQuestReward |
| Automation.lua | Existing guards, NPC event sequencing, retries and execution | UI storage access |
| UI/Prepick.lua | View and UI interaction/async display controller; invokes model operations | Hand-in decisions/execution |
| UI/PrepickData.lua | UI reads and display record conversion, invokes same reward policy | Eligibility checks or automation mutation |
| Glow.lua | Existing glow view; invokes same reward policy | Own independent pre-pick resolution |

## Explicit contracts and identifier meanings
Lua annotations brand identifiers without changing the underlying WoW numeric API types.
- QuestAutomator_QuestID: stable quest identity (positive integer). Never a log index.
- QuestAutomator_RewardItemID: stable item identity (positive integer). Persist this.
- QuestAutomator_RewardChoiceIndex: current offered choice index (positive integer). Never persist this.
- QuestAutomator_PrePickResolutionStatus: none | matched | pending | unavailable | ambiguous.
- QuestAutomator_RewardChoice: existing gathered record, including index, itemID, lootType, loaded.
- QuestAutomator_PrePickResolution: status, rewardItemID?, rewardChoiceIndex?, choice?.
- Model.GetSelectedRewardItemID(questID) -> rewardItemID?
- Model.SetSelectedRewardItemID(questID, rewardItemID) -> changed:boolean (valid positive IDs only).
- Model.ClearSelection(questID) -> changed:boolean.
- Model.ResolveSelectedRewardChoice(questID, offeredChoices) -> resolution.
- Model.GetRevision() -> monotonic revision for UI cache invalidation.
- Model.GetSelectionCount() -> QuestAutomator_PrePickSelectionCount, for diagnostics without exposing storage.
- TurnInResolver.Resolve(context) -> tagged submit/manual/wait result plus prePickStatus.
  matched -> submit current index, reason='prepick', and original-compatible rewardDecision detail;
  pending -> wait with no actionable index;
  otherwise -> original Rewards.Evaluate decision translated to the tagged result.
  See TURN_IN_RESOLVER.md for the authoritative contract; no critical undefined terms remain.

## Lifecycle and safeguards
- Model initializes after Core.InitDB via ADDON_LOADED; preserve valid existing selections, discard malformed IDs.
- Model cleanup handlers load before picker handlers, so the picker reads already-cleaned state.
- Window close does not forget picks. Clicking the selected item again clears only that quest.
- Sample preview uses no real questID and cannot write a selection.
- Existing Auto.Blocked, MayTurnIn, money checks, retry identity/token checks and SendOnce remain unchanged.
- Selection changes refresh the picker but do not immediately execute a hand-in. Glow integration is deferred.
- A caller invoking the resolver alone does not have permission to act: the controller owns safeguards.

## Phases / verification
- [x] Implement model, lifecycle and identifier validation with pure resolution tests.
- [x] Implement resolver delegating to unchanged original scoring; test missing/reordered/unloaded/duplicate choices.
- [ ] Connect Glow.Decide to resolver (deferred); Auto.Choose and picker are connected, messages updated.
- [x] Verify per-quest isolation, persistence, cleanup, manual-mode and quality override, and invalid-pick fallback locally.
- [x] Re-run gossip-to-zero-reward regression and all UI/client-shape/locale smoke tests locally.
- [x] Test disabled/paused/modifier/ignored NPC/ignored quest/repeatable/money safeguards with selected rewards locally.
- [ ] Owner verifies actual chosen item at a live multi-choice turn-in on each client.

## Open questions / deferred work
- Full separation of view rendering from UI scheduling is deferred until this boundary is tested in game.
- No new client API abstraction is needed for itemID-to-current-choice resolution; future differences require verified contracts.
- Duplicate offered item IDs cannot encode a unique preference with itemID-only storage; fallback to original policy rather than guess.
- In-game validation remains necessary; mock tests do not certify actual client API behaviour.