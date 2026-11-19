# Settings layout review and unfinished-feature plan

Scope of this change: presentation/layout only. No automation/resolver policy changes.
Future gameplay changes require one local-test + owner in-game-test checkpoint each.

## Screenshot review (all settings screenshots in Assets)
| Screenshot | Observation | Layout correction |
|---|---|---|
| Settings_Main | Generally readable; parent/child checkbox grouping is clear, but layout depends on relative offsets and assumes short labels. | Preserve grouping with explicit per-section indentation and wrap checkbox labels within available width. |
| Settings_RewardSelection | Readable at this width; reward-mode and six-quality radio lines cannot wrap at narrower widths. 'Original' is implementation history, not a user-facing distinction. | Measure complete radio-label cells, wrap whole choices, rename section Reward selection. |
| Settings_RewardTiers | First tier label wraps; its options nearly collide with the next tier. Other rows have inconsistent gaps; slider/border spacing comes from unrelated guessed heights. | Stack using actual measured widget heights; reserve space for multiline titles, radio rows and slider end labels. |
| Settings_RewardWearibility | Long stat-weight text wraps while its holder remains one line; panel has excess trailing space. | Measure notes and long labels, use those same heights for next-row placement and section border. |
| Settings_PrePickFeedback | Generally readable; explanatory note and long unlock/chat labels depend on fixed sizing. | Wrap measured notes/checkbox labels, preserve the unlock indentation and align the following top-level checkboxes. |

Underlying defect: Section.Add counted one manually supplied height toward its border, but anchored the
next widget to the previous widget's different actual height. Note always returned a 14-high holder;
wrapped RadioRow always returned 40. All placement, border and scroll sizing now share measured heights.

## Layout mechanism and terms
| Term/symbol | Mechanism / exact meaning |
|---|---|
| QuestAutomator_SettingsPixels | WoW UI coordinate units, not physical screenshot pixels |
| SettingsLayout.Flow | Pack complete radio+label cells into rows; measure taller wrapped labels before advancing the next line |
| SettingsLayout.Stack | Assign row x/y/width/height from measured widget size, minimum height, gap, and indentation |
| row gap | Positive distance from previous row bottom to next row top |
| row indentation | Offset relative to the section content left edge, not a chained widget anchor |
| LayoutPage | Re-measure all rows for current viewport width, position them, size content, clamp scroll |
| viewport width | ScrollFrame width; content may shrink with it instead of enforcing a 620-unit minimum |

No critical undefined layout terms remain. Frame/font metrics are still client-rendered: mocks test
layout invariants, not actual font rasterization or visual appearance.

## Current work / verification
- [x] Inspect all five settings screenshots.
- [x] Implement shared measured flow/stack layout and responsive page/section widths.
- [x] Preserve setting keys, defaults, callback actions, placeholder semantics and existing automation behaviour.
- [x] Run pure layout tests and actual-widget mock geometry checks at varied widths/font sizes (280 rows per client/locale run).
- [x] Run both client-shape smoke suites in enUS/zhCN and all resolver/model regressions; Lua syntax and source-boundary checks pass.
- [ ] Owner publishes/reloads and checks all five sections visually before considering layout finished.

## Plan for unfinished features — proposed, not implemented in this layout pass

### 0. Confirm current pre-pick consumption
Before any new automation-affecting work: owner confirms a non-default pre-picked item is actually
received, the pick survives reload, and another quest's stored selection is untouched.

### 1. Shared decision display (NPC glow and /qam why)
- Route both views through TurnInResolver instead of independently invoking the old scorer.
- Reuse the existing verified read paths; handle NPC and quest-log reward contexts separately.
- Show selected pre-pick, automatic choice, manual recommendation, loading, and unavailable-pick fallback.
- Keep an executable reward index distinct from a merely recommended item; manual/wait never authorizes submission.
- Verify both clients' reward button identities and log selection restoration; no API-global hooks/replacements.
- Local tests: displayed item and reason agree with resolver; missing data and disabled automation don't execute actions.
- STOP: owner checks glow and /qam why against selected pre-picks and unpicked quests.

### 2. Wearable-item and equipped-item facts (read-only first)
- Define a small RewardFacts snapshot: usability, armour/weapon class, equipped slots, item levels, loading status.
- Implement learnable versus currently trained weapon checks only after verifying live APIs on each client.
- Keep unknown/missing API answers distinct from false; unknown equipped-item data is not an empty slot.
- Cover paired rings/trinkets, valid dual-wield offhands, shields, and two-handed replacement explicitly.
- Exercise class/level armour transitions and weapon restrictions with fixtures; display results before policy consumes them.
- STOP: owner compares factual results against real character skills and equipped gear.

### 3. Tier policy + sidegrade band (one staged implementation)
Proposed compatibility rule: add an explicit **Tier rules** reward mode; retain Best fit, Vendor value
and Manual unchanged. Do not silently reinterpret existing users' saved reward modes.
- Implement a pure TierRewardPolicy invoked only by TurnInResolver, not NPC dialog handlers.
- Inputs are verified RewardFacts, current choices, settings and player profile; return submit/manual/wait.
- Precedence: existing controller safeguards -> valid pre-pick -> quality gate -> hard-to-value gate ->
  qualifying upgrade/sidegrade candidates -> value fallback. New submission vetoes, if introduced, precede pre-picks.
- Tier 1 identifies trinkets/relics, Use/proc effects, unvalued Equip effects and non-equipment; unknown facts wait.
- Count qualifying candidates BEFORE deciding tier 2 or 3: two or more means tier 4, even if only one is a large upgrade.
- Exactly one candidate: delta > band is tier 2; within +/- band is tier 3. None qualifies: tier 5.
- Add boundary tests at -band, +band, band+1; missing gear data; empty valid slots; multiple candidates; and every action setting.
- Quality behaviour, non-equipment exceptions, and how weapon/trinket switches interact with Tier rules must be documented.
- Initially compare tier results in read-only diagnostics; enable the selectable mode only after factual outputs are verified.
- STOP after read-only comparison; STOP again after enabling Tier rules for actual turn-ins.

### 4. Value-source contract and vendor provider
- Add RewardValuation result fields with semantic units: totalCopper, source, availability and optional age/confidence.
- Vendor total equals unit sell price times reward count. Unknown is not the same as a known zero value.
- Read provider data only; valuation must never sell, auction, disenchant, or manipulate inventory.
- Use the value source only where the selected policy requests value ranking; do not override pre-picks or safeguards.
- STOP: owner verifies prices/stacks and tier-5 selection using known vendor values.

### 5. Auction valuation provider
- Select one supported installed addon/provider and verify its current API before coding an adapter.
- Normalize unit/stack values and server/region scope; identify estimates and stale/unavailable data.
- Default proposed fallback when the selected provider has no quote: vendor value, visibly labelled as fallback.
- Test absent provider, zero/unknown values, stale quotes, stack counts and ties.
- STOP: owner checks displayed prices against the provider, then actual automatic choice.

### 6. Disenchant valuation provider
- Use a verified provider's expected disenchant value rather than inventing loot probabilities.
- Define whether this is market-value ranking regardless of player profession, or only for currently disenchantable items.
- Apply the same explicit availability and fallback contract as auction pricing.
- STOP: owner checks known items and no-provider cases before enabling automatic choices.

## Decisions requiring owner agreement before their implementation
1. Add **Tier rules** as an explicit reward mode (recommended) versus replacing Best fit?
2. In Tier rules, should weapon/trinket switches apply, or should their per-tier actions be authoritative?
3. For auction/DE quotes, vendor fallback (recommended) or leave the quest manual when data is unavailable?
4. Is disenchant value hypothetical market value or restricted by the character's enchanting capability?

Until their implementation checkpoints pass, the corresponding controls remain clearly marked
Not implemented and changing them must not change automation. This plan does not mark those features done.