# Stable turn-in decision resolver

Refines and supersedes the proposed RewardSelectionPolicy.Evaluate contract in
[PREPICK_MODEL_AND_POLICY.md](PREPICK_MODEL_AND_POLICY.md). The unused RewardSelectionPolicy.lua
prototype was removed; TurnInResolver is the single production policy entry point.

## Current checkpoint: pre-pick consumption (v2026.11.18.1709)
The owner confirmed the pass-through turn-in checkpoint works. The resolver now consults the loaded
PrePickModel for multiple-choice quests. Matched item IDs override original reward recommendations;
pending data waits; absent/ambiguous rewards fall back to the unchanged original scoring policy.
Automation.lua is byte-identical to the owner-confirmed pass-through checkpoint. Model migration
and consumption require no further controller edits. Glow integration remains deferred.
UI storage access now delegates to the model; the picker displays the resolver's decision. A single
description branch in Rewards.Describe labels a matched selection as your pre-pick. Original
Gather/Evaluate algorithms are unchanged. Existing valid pre-picks become active without schema migration.
Selections clear only on actual hand-in/abandon or explicit user clearing, never on an attempted turn-in.
The minimap still toggles the picker and exposes pending/loading/unavailable statuses.

## Goal
Separate whether to auto-submit and which reward to select from NPC dialog execution.
Future pre-picks and submission rules must change resolver policy, not dialog event handlers.
The confirmed IsQuestComplete fallback remains untouched.

## Responsibilities
| Component | Responsibility |
|---|---|
| Existing automation controller | Events, existing permission/safety checks, reading the current offer, retries, identity validation, and executing GetQuestReward |
| Turn-in resolver | Decide submit/manual/wait and resolve the current reward index; never execute an action |
| PrePickModel | Store item-ID preferences and resolve them against offered choices; no quest API or UI calls |
| Original Rewards module | Original scoring and hand-off rules, delegated to by the resolver |
| Pre-picker/glow views | Display the shared decision; never grant permission to turn in |

## Proposed contract
`NS.TurnInResolver.Resolve(turnInContext) -> turnInDecision`

`NS.TurnInResolver.IsDecisionValid(turnInContext, turnInDecision) -> valid`
checks the action tag, required reason, submission-index bounds and offered-item identity.
The controller catches resolver/validation exceptions and leaves the dialog manual. It never
falls back to an automatic action after an invalid response. No critical undefined terms remain.

All record fields have semantic types (Lua annotations; runtime WoW primitives stay unchanged):

| Context field | Semantic type / meaning |
|---|---|
| questID | QuestAutomator_QuestID?; stable identity when known, nil otherwise, never the controller's boolean sentinel |
| rewardChoiceCount | QuestAutomator_RewardChoiceCount; current NPC offer count, including 0/1 |
| rewardChoices | QuestAutomator_RewardChoiceList; gathered current-offer snapshot for multiple choices, empty for 0/1 to preserve original behaviour |
| settings | QuestAutomator_RewardPolicySettings; original reward settings and explicitly implemented new policy only |
| player | QuestAutomator_PlayerRewardContext?; original class/stat context, unnecessary for 0/1 choices |

| Decision field | Semantic type / meaning |
|---|---|
| action | QuestAutomator_TurnInAction: submit / manual / wait |
| rewardChoiceIndex | QuestAutomator_RewardChoiceIndexOrNone; required only for submit, 0 for no choice, otherwise valid current offered index |
| reason | QuestAutomator_TurnInReason; explicit original-policy, pre-pick, loading or submission-rule reason |
| rewardDecision | QuestAutomator_OriginalRewardDecision?; original-compatible detail for explanations and recommendation display |
| prePickStatus | QuestAutomator_PrePickResolutionStatus?; none/matched/pending/unavailable/ambiguous for multi-choice resolution |

Decision is a tagged result: manual/wait cannot be interpreted as submit. No magic index nil or boolean
overloading. A missing/invalid resolver result fails to manual, never falls through to submission.

## Controller pseudocode
```text
QUEST_COMPLETE -> existing deferred action
    existing TurnInAllowed checks
    read current quest and reward offer
    decision = TurnInResolver.Resolve(context)
    submit -> existing TakeReward(currentQuestID, decision.rewardChoiceIndex, detail)
    manual -> existing leave-open path and explanation
    wait   -> existing bounded load/retry path; recheck quest identity and permission before acting
```

CompleteQuest at the progress stage merely advances the dialog. The resolver controls final
submission at QUEST_COMPLETE, not quest acceptance or gossip navigation.

## Invariants
- The resolver is consulted for 0, 1, and multiple reward choices. Zero/one branches cannot bypass it.
- Initial implementation preserves original 0 -> GetQuestReward(0), 1 -> GetQuestReward(1), and
  multi-choice original scoring/manual/pending behaviour exactly.
- The controller retains enabled, turnIn, pause, ignore, repeatable, money, duplicate-action and retry guards.
- Resolver policy may further restrict submission, but cannot override controller safeguards.
- Future explicit submission vetoes precede reward choice. Player pre-picks override automatic reward
  recommendations, not submission vetoes.
- Resolve stored item IDs against the current offer every time; never persist an index.
- Missing/ambiguous stored reward -> original policy; unidentified/unloaded data -> wait, not a guessed pick.
- UI-only placeholder settings remain inert until separately implemented and tested.
- No replacing WoW globals, Auto functions or Rewards.Evaluate with wrappers/monkey patches.
- No broad client adapter rewrite. Client differences only enter through individually verified read contracts.

## Incremental checkpoints (mandatory stops)
- [x] A implementation: model owns picker storage/lifecycle; persistence and isolation tests pass.
- [x] B implementation: resolver pass-through connected for 0/1/multiple choices; Lua syntax,
  72 multi-choice parity cases, controller safeguards, retries and malformed-result tests pass.
- [x] B in-game checkpoint: owner reported successful automatic turn-in and requested consumption next.
- [x] C implementation: saved item-ID precedence in resolver; local reorder/loading/safety tests pass.
- [ ] C in-game checkpoint: STOP for owner selection and actual item receipt (plus persistence/review).
- [ ] D: connect glow/shared explanations; local tests, STOP for in-game display verification.
- [ ] Each later automation-affecting feature gets its own local tests and in-game checkpoint.

## Open / deferred
- Concrete new submission rules are not implemented or enabled by this interface extraction.
- Future runtime client abstractions require explicit data semantics/provenance and live verification.
- Keep existing controller checks in their current locations rather than relocating them in this change.
- Separate the pre-picker's rendering from its UI scheduling later if needed; do not combine that work
  with the turn-in resolver integration.