# QuestAutomator — fork of SmartQuestAutomation with Classic Era support

Status: **Historical design, superseded by the restored-runtime baseline.** Owner: Kuro.

The owner directed removal of Client.lua and Engine.lua and restoration of the ZIP's original
runtime without refactoring. Retained UI options absent from the original are saved-only placeholders.
See [Restored runtime / UI baseline](RESTORED_UI_BASELINE.md) for current behaviour and testing.

## 1. Goal

Fork `SmartQuestAutomation` (qqytqqyt, v0.3.0, Forever-only) into **`QuestAutomator`**, a git repo in this
workspace, that runs on **WoW Forever (16001)** *and* **Classic Era / Anniversary / Hardcore (11509)** from a
single TOC. Pure rename + port: no behaviour changes to the automation itself.

## 2. Decisions (from owner, 2026-11-17)

| # | Decision |
|---|---|
| Target flavours | Forever (primary, 16001) + Classic Era (11509). Not MoP, not TBC/Wrath. |
| TOC | One file, `## Interface: 16001, 11509`; runtime `WOW_PROJECT_ID` checks where code paths differ. |
| Name | Folder/TOC/Title `QuestAutomator`. No `.Kuro` suffix (whole name changes). |
| Globals | `QuestAutomator` (handle), `QuestAutomatorDB`, `QuestAutomatorCharDB`, `QuestAutomator_OnAddonCompartment{Click,Enter,Leave}`, frame `QuestAutomatorMinimapButton`, slash key `SLASH_QUESTAUTOMATOR1/2`. |
| Slash | `/qam`, `/questautomator` (`/qa` avoided: common collision). |
| Chat prefix | `Quest Automator` |
| Settings migration | None. Fresh `QuestAutomatorDB`. |
| Git | New repo in `QuestAutomator\`. `SmartQuestAutomation\` stays as untouched upstream reference (like `MoveMyBags\`). |
| Classic scope | Full: core flow + Era talent detection + Era stat strings + XP bar on `MainMenuExpBar`. Degrade silently where an API truly does not exist. |
| zhCN | Keep maintained; new keys added to both locales. |
| Behaviour | No changes (defaults, minimap angle etc. untouched). |

## 3. Upstream facts

- Source: `C:\PROJECTS\3P_WoWAddons\SmartQuestAutomation\` (not a repo). TOC `X-Website: https://github.com/qqytqqyt/SmartQuestAutomation`.
- **License: TBD** — check upstream repo before first push (Phase 0).
- 9 Lua files, 2 locales, ~3,400 lines, no libraries. Every client call goes through `NS.Call(path, ...)` (pcall +
  `NS.features[path]` tracking shown by `/sqa debug`) — the port is mostly adding Classic branches, not rewriting.

## 4. Classic Era API audit

Known-good on Era 1.15.x (present, same signatures): `C_GossipInfo.GetAvailableQuests/GetActiveQuests/SelectAvailableQuest/SelectActiveQuest/CloseGossip`,
`GetNumAvailableQuests/GetNumActiveQuests/GetAvailableTitle/GetActiveTitle/GetAvailableQuestInfo/GetActiveQuestID/SelectAvailableQuest/SelectActiveQuest`,
`AcceptQuest/CompleteQuest/GetQuestReward/ConfirmAcceptQuest/CloseQuest/GetQuestID/GetTitleText/IsQuestCompletable/GetQuestMoneyToGet/QuestGetAutoAccept/AcknowledgeAutoAcceptQuest/QuestFlagsPVP`,
`GetNumQuestChoices/GetQuestItemInfo/GetQuestItemLink/GetQuestItemInfoLootType/GetNumQuestLogChoices/GetQuestLogChoiceInfo/GetQuestLogItemLink/GetQuestLogRewardXP`,
`C_QuestLog.IsOnQuest/IsQuestTrivial/IsRepeatableQuest/GetTitleForQuestID/GetNumQuestLogEntries/GetInfo/IsComplete/IsFailed/GetSelectedQuest`,
`C_Item.GetItemInfo/GetItemInfoInstant/GetItemStats/RequestLoadItemDataByID/GetItemSubClassInfo`, `C_TooltipInfo.GetQuestItem/GetQuestLogItem`,
`C_AddOns.GetAddOnMetadata`, `Settings.*` proxy API, `hooksecurefunc`, `QuestInfo_Display`, `QuestInfo_ShowRewards`, `QuestInfoFrame.rewardsFrame.RewardButtons`,
`UnitClassBase`, `UnitXP/UnitXPMax/GetMaxPlayerLevel/IsXPUserDisabled`, `C_PlayerInteractionManager.IsInteractingWithNpcOfType`.

**To verify in Researching phase (ground truth, not memory):** `GetAvailableQuestInfo` return order on Era; whether
`C_Item.GetItemStats` key names on Era are `ITEM_MOD_*_SHORT`; whether `QuestInfoFrame.questLog` and `rewardsFrame.RewardButtons`
exist in Era's `QuestInfo.lua`; `ActionButtonSpellAlertTemplate` presence (border fallback exists anyway).

| Area | Forever (current) | Era | Action |
|---|---|---|---|
| Talents (hunter Survival) `Rules.Talents` | `C_SpecializationInfo` + `C_Traits` | `C_SpecializationInfo.GetSpecializationInfo(tab)` → `specId, name, desc, icon, role, primaryStat, pointsSpent`; 3 tabs, tab 3 = Survival. `GetTalentTabInfo` is a deprecated shim (cvar-gated) | `Client.TalentGroups()` |
| Tooltip stat strings `Rewards.FORMATS` | rating-based ("Increases your hit by %s.") | vanilla text: "Improves your chance to hit by %s%%", "Improves your chance to get a critical strike by %s%%", "+%s Defense", "+%s Attack Power", "Increased Defense +%s"… | Add `Rewards.FORMATS_CLASSIC` table (enUS + zhCN), merged into `FormatsFor(tag)` after live global. Pattern compiler must accept `%%`. Needs ground-truth strings from Era GlobalStrings. |
| Stat keys | `HIT_RATING`, `CRIT_RATING`, `DEFENSE_SKILL_RATING` | same keys reused for % hit/crit and flat defense (weights are per-point; vanilla amounts are small numbers, acceptable) | Reuse keys; document the approximation |
| XP bar `XPBar.Bars()` | `StatusTrackingBarManager.barContainers[*].bars[Experience]` | **Same** (verified: Era 1.15 `Blizzard_ActionBar/Classic/StatusTrackingBar.xml`, `ExpStatusBarTemplate`; `MainMenuExpBar` no longer exists) | none; atlases may be absent → colour fallback exists |
| `C_QuestLog` | full | **only** `IsOnQuest, GetQuestInfo(id)→title, IsQuestFlaggedCompleted, ShouldShowQuestRewards, GetMaxNumQuests…` | `Client.QuestTitle(id)`, `Client.IsQuestTrivial(id)`, `Client.IsQuestRepeatable(id)`, `Client.QuestLogEntries()` over `GetQuestLogTitle(i)` |
| Quest-log reward panel | `QuestInfo_Display(QUEST_TEMPLATE_LOG)` → `QuestInfoFrame.rewardsFrame.RewardButtons`, `button.objectType` | `QuestFrameItems_Update("QuestLog")` → `_G["QuestLogItem"..i]`, `button.type="choice"`, `button.rewardType="item"`; selected quest via `GetQuestLogSelectedID()`; `GetNumQuestLogChoices()`/`GetQuestLogChoiceInfo(i)` take **no questID** | `Client.RewardLayoutHooks()` (function names to hooksecurefunc), `Client.RewardContext()` → `{ questID, source, buttons, questLog }` |
| Greeting row | `GetAvailableQuestInfo(i)` → `isTrivial, frequency, isRepeatable, isLegendary, questID` | `isTrivial, isDaily, isRepeatable, isLegendary` (no questID) | `Client.AvailableQuestInfo(i)` |
| `GetQuestItemInfo("choice", i)` | 6 returns (itemID last) | 5 returns | already falls back to link |
| Item stats | `C_Item.GetItemStats(link)` | legacy `GetItemStats(link)` | `Client.ItemStats(link)` |
| Addon compartment | TOC `AddonCompartmentFunc*` | ignored by Era | leave |
| Minimap right-click menu | `MenuUtil.CreateContextMenu` | present on 1.15.3+; else falls back to settings page | leave |
| Minimap radius | live `Minimap:GetWidth()` | Era map ~140px, live size works | leave |
| Secret values | `issecretvalue`/`canaccessvalue` | absent → `NS.Safe` passthrough | leave |
| `NS.version` | `C_AddOns.GetAddOnMetadata` | present on 1.15 | leave |

Ground truth: `_EXTERNAL_APIS/wow_classic_era_quest_ui_api.md`; sources in `_ref/blizzard/classic_era/`.

Nothing in this table is impossible on Era; every row has a Classic equivalent. "Degrade silently" applies
only to UI chrome that has no Era counterpart (addon compartment).

## 4a. Client adapter layer (`Client.lua`)

Flavour differences are isolated in **one new file**, `Client.lua`, loaded right after `Core.lua`. Feature
code (`Rules`, `Rewards`, `XPBar`, `Automation`) calls `NS.Client.*` and never tests `WOW_PROJECT_ID` itself.

```lua
-- Client.lua: one implementation table per flavour, selected once at load.
local Client = { flavour = "forever" | "classic_era" }
NS.Client = Client

-- Talents: points spent per tree, in display order. Same shape for both flavours.
--   -> { groups = { { name, spent, orderIndex, skillLineID? }... }, source = "traits"|"talents"|"none" }
function Client.TalentGroups() end

-- Quest-giver available-quest row (greeting panel); normalises GetAvailableQuestInfo's return order.
--   -> { isTrivial, frequency, isRepeatable, questID }
function Client.AvailableQuestInfo(index) end

-- Tooltip stat format strings for this flavour and locale, keyed by ITEM_MOD_* tag.
--   -> { ITEM_MOD_HIT_RATING = { "Improves your chance to hit by %s%%", ... }, ... }
function Client.StatFormats() end

-- Experience bars to overlay and how to hook them.
--   -> list of { frame, statusBar, Hook = function(frame, onChange) }
function Client.ExperienceBars() end

-- Max level the client enforces (GameRulesUtil on Forever, GetMaxPlayerLevel on Era).
function Client.MaxLevel() end
```

Selection rule, in order: `WOW_PROJECT_ID == WOW_PROJECT_CLASSIC` → `classic_era`; else `forever`
(Forever reports `WOW_PROJECT_MAINLINE`). Each flavour table is complete; a missing implementation is a bug,
not a fallback. `NS.Client.flavour` and every adapter's chosen path are listed by `/qam debug`.

Existing Forever logic moves *into* the Forever adapter unchanged (e.g. `Rules.Talents` body →
`Client.forever.TalentGroups`); `Rules.Talents()` becomes a thin call to `NS.Client.TalentGroups()`.

Names follow the linguistic-keying rule: adapter functions are verb-noun and return **named-field tables**,
never positional tuples, so callers cannot mis-order Era vs Forever return values.

### Rewards.FORMATS split
`Rewards.FORMATS` (Forever rating strings) → `Client.forever.STAT_FORMATS`; new `Client.classic_era.STAT_FORMATS`
from Era GlobalStrings. `Rewards.FormatsFor(tag)` = live `_G[tag]` first, then `NS.Client.StatFormats()[tag]`.
`CompilePattern` gains literal-`%%` support (Era hit/crit strings end in `%%`).

## 5. Phases

### Phase 0 — Fork scaffolding
- [ ] Fetch upstream repo page; record license in `README.md` (`X-Upstream`, attribution). If no license: note it, ask owner.
- [ ] Copy `SmartQuestAutomation\` → `QuestAutomator\`; rename TOC; `git init`; `.gitignore` (mirror `ChatSync/.gitignore`).
- [ ] TOC: `## Interface: 16001, 11509`, Title `QuestAutomator`, Author `qqytqqyt (fork maintained by Kuro)`, `## Version: @project-version@`, `X-Upstream`, renamed SavedVariables / compartment funcs.
- [ ] Rename every global (Core.lua handle, SavedVars, compartment funcs, slash vars, minimap frame name) and every `/sqa` text in both locales to `/qam`; header comments `Smart Quest Automation:` → `QuestAutomator:`; chat prefix.
- [ ] `README.md`, `CHANGELOG.md` (`Unreleased: fork, rename, Classic Era`), `LICENSE` per upstream.
- [ ] Update `PROJECT_STRUCTURE.md` tree (+ note SmartQuestAutomation is reference only).
- [ ] Grep check: zero occurrences of `SmartQuest`/`sqa`/`SQA_` outside the reference folder (keep `SQA_` setting variable names? → **rename to `QAM_`**, they are Settings-API variable IDs and must not collide).
- [ ] Commit `Fork SmartQuestAutomation 0.3.0 as QuestAutomator`.

### Phase 1 — Era: load clean, core flow
- [ ] Research (ground truth) the "to verify" items in §4 from Era `QuestInfo.lua`, `QuestFrame.lua`, `MainMenuBar` XML (Gethe wow-ui-source `classic_era` branch); save notes to `_ref/blizzard/classic_era/` + `_EXTERNAL_APIS/`.
- [ ] New `Client.lua` (§4a) with both flavour tables; move existing Forever-specific bodies into `Client.forever`; TOC load order `Core, Client, Rules, ...`.
- [ ] `Client.AvailableQuestInfo` used by `Automation.ActGreeting`.
- [ ] Fix anything the research shows differs (e.g. `GetAvailableQuestInfo` arity).
- [ ] Owner tests on Era: accept, progress, complete, 2-choice reward, pause key, ignore. Capture `/qam debug` + `/qam log`.

### Phase 2 — Era: accurate "best fit"
- [ ] `Client.classic_era.TalentGroups()` via `GetNumTalentTabs`/`GetTalentTabInfo`; `Rules.Talents` computes `survivalDominant` from the shared shape.
- [ ] `Client.classic_era.STAT_FORMATS` from Era GlobalStrings (enUS, zhCN); extend `CompilePattern` for literal `%%`.
- [ ] Unit-style sanity: run `Rewards.ParseStatLine` against a list of real Era tooltip lines in a scratch Lua test (plain `lua`/`luajit` if available on PATH; otherwise document in-game `/qam why` check).

### Phase 3 — Era: XP bar overlay on `MainMenuExpBar`
- [ ] `Client.classic_era.ExperienceBars()` → `MainMenuExpBar`; `XPBar.Bars()` consumes the adapter list; verify overlay anchors to the bar's fill rect.
- [ ] Owner visual check on Era.

### Phase 4 — Release
- [ ] CHANGELOG, README (both flavours, `/qam` commands), `cmd\publish.cmd` run by owner, `cmd\release.cmd` by owner.

## 6. Reward priority engine (replaces `rewardMode fit|value|manual`)

Decisions from owner, 2026-11-17. Replaces §"Scoring" of upstream `Rewards.Evaluate`. The question changes from
*"which reward fits my class best?"* to *"is any reward an upgrade over what I wear, and is the decision safe to
automate?"*. Users mostly want quests auto-handled; the engine only stops for things a human should decide.

### 6.0 THE RULE (owner, stated from the beginning; everything below is how the code gets there)

1. **One obvious upgrade** for the player → follow the player's setting, **default `upgrade`** (take it).
2. **Two or more obvious upgrades** → follow the player's setting, **default `ask`** (coin on the best, window stays open).
3. **Neither** → pick the **best cash item**, follow the player's setting, **default `cash`**.

"Best cash item" = the reward with the **highest vendor value, full stop**. Wearability, armour class and
stats are **not** considered in step 3: nothing on offer beats what is worn, so every reward is going to the
vendor and the one worth the most gold is the right pick. (A 2026-11-20 change made step 3 prefer wearable
items, and it then put the coin on a 2s81c cloth belt over 4s69c boots. Reverted 2026-11-21:
`Rewards.ByValue(pool)` over the whole pool.)

**The druid hammer-vs-gun episode (Old Ironforge Incursion) was misdiagnosed on 2026-11-20.** The hammer IS a
druid upgrade on Forever and should have gone through step 1 — it only looked like "nothing fits" because the
druid's weapon-DPS weight was wrong at the time. The real rule, now encoded per flavour via
`Client.StatWeightOverrides()` → `Rules.ApplyClientWeightOverrides`:

| Flavour | Druid Cat / Bear form damage | `DRUID.MELEE_DPS` |
|---|---|---|
| **Forever** | **based on weapon DPS** (and weapon procs apply) | 4.0 (shared default) — a better-DPS hammer is an upgrade |
| **Classic Era** | **ignores weapon DPS** (level + attack power only) | 0 (Era client override) — a hammer upgrades only on its stats |

Any other "the game itself works differently on this flavour" fact belongs in the flavour's client file the
same way — never as an `if flavour` in `Rules.lua` / `Rewards.lua`.

**Tier dispositions are three explicit verbs** (`UIState.TIER_ACTIONS`, saved as `tierNAction`), selectable on
every tier:

| Value | Meaning |
|---|---|
| `ask` | recommend only: glow the engine's suggestion, leave the reward window open |
| `upgrade` | auto-pick the best stat upgrade over what is worn (on tier 5 there is none → behaves as `cash`) |
| `cash` | auto-pick the highest vendor-value reward in the **whole** pool, wearable or not |

The earlier two-value enum `auto` / `recommend` was retired 2026-11-21 because `auto` meant "take the upgrade"
on tiers 1–4 and "take the cash" on tier 5 — the ambiguity that let the two get confused. Saved values migrate
in `UIState.MigrateTierAction` (`recommend`→`ask`; `auto`→`upgrade`, or `cash` on tier 5) and `Rewards.TierAction`
accepts the legacy words as a belt-and-braces fallback.

### 6.1 Tiers — evaluated in order, first match wins

| Tier | Condition (over the set of choices) | Default action | Setting key |
|---|---|---|---|
| **Q** | Any choice has quality ≥ `manualQuality` (default Rare) — kept as a global gate | ask | `manualQuality` (existing) |
| **1** | **Ambiguous** — a trinket or relic/libram/idol/totem among the upgrades; a weapon or trinket whose "pick" setting is off; or **no equipment at all on offer** (only consumables: potions, food, bags, recipes — implemented 2026-11-21, `Rewards.IsEquipment`). Message: *"ambiguous rewards, make a manual selection"*. The `Use:` / proc-line detection from the first design is **not** implemented. | `ask` | `tier1Action` |
| **2** | Exactly one **best-wearable** choice is an **upgrade** (= rule step 1) | `upgrade` | `tier2Action` |
| **3** | *(unused — the original ilvl-sidegrade tier; stat-based upgrades made it redundant. Setting is saved only.)* | `upgrade` | `tier3Action` |
| **4** | **Two or more** best-wearable choices are upgrades (= rule step 2) | `ask` | `tier4Action` |
| **5** | Nothing qualifies → **best cash item**: highest vendor value over **all** choices, wearable or not (= rule step 3) | `cash` | `tier5Action` |

**Upgrade** (as implemented, replacing the ilvl test of the first design): the reward's class-weighted stat value
(`Rewards.StatValue`) exceeds the worn item's by at least the **upgrade threshold** — setting `upgradeBand`,
percent of score, slider 0–50, **default 5%** (owner 2026-11-21; was 10). Any gain counts when the slot is empty
or the worn item is worth nothing. Below the threshold a reward is a sidegrade and is treated as cash. Items the
class cannot equip never count.

`ask` on every tier = the old `manual` mode; no separate master setting.

Future (owner, not now): a per-class **stat priority** veto so e.g. Strength cloth is not an upgrade for a Mage.
Weights (`Rules.WEIGHTS`) survive today only as the **tie-break inside a tier** (which of two tier-2 items to glow,
which item to glow in tier 4); they never veto. Settings UI shows the current class's weights read-only.

### 6.2 Definitions

- **Best-wearable** (armour): the piece's armour subclass equals `Rules.PreferredArmor(class, level)` — the class's
  *best* class at the current level (Warrior/Paladin: mail <40, plate ≥40; Hunter/Shaman: leather <40, mail ≥40;
  Rogue/Druid leather; casters cloth). **Lighter armour** (cloth on a shaman, leather on a warrior; `fit.lighter`)
  competes as an upgrade **only when no best-wearable piece is an upgrade** (owner decision 2026-11-21, lenient
  rule): if any best-type upgrade exists, lighter pieces are sidelined (`fit.why = "lighter"`) and do not count
  toward tier 4, so cloth + leather gloves on a L1 shaman is ONE upgrade → tier 2 → auto. If only lighter armour
  is on offer it goes through the tiers normally. Neutral slots (cloak, neck, ring, trinket, held-in-off-hand,
  shirt, tabard) are always wearable and never lighter. Shields: War/Pal/Sham.
  The level-40 transition is handled by the existing `ARMOR_PROGRESSION` table.
- **Best-wearable** (weapon): setting `weaponProficiency = "learnable" | "usable"` (default `learnable`).
  `learnable` = the subclass is in `Rules.WEAPONS[class]` (the class can train it at some trainer).
  `usable` = the character currently has the skill (`Client.HasWeaponSkill(subclass)`; Era: `GetSkillLineInfo`
  walk; Forever: TBD in Researching). Ranged/melee kind preference (hunter Survival) remains a filter when both kinds
  are offered.
- **Worn ilvl** (per slot, `Client.WornItemLevel(equipLoc)`): `C_Item.GetItemInfo(GetInventoryItemLink("player", slotID)).itemLevel`,
  empty slot = 0. Slot mapping from `INVTYPE_*` → inventory slot IDs: FINGER → min(11,12), TRINKET → min(13,14),
  WEAPON (one-hand) → min(16,17) where 17 holds a weapon, 2HWEAPON → 16 (and 17 if occupied: compare to max),
  WEAPONMAINHAND → 16, WEAPONOFFHAND/SHIELD/HOLDABLE → 17, RANGED/RANGEDRIGHT/THROWN/RELIC → 18, else the
  single slot. Table lives in `Rules.EQUIP_SLOTS`.
- **Reward ilvl**: `C_Item.GetItemInfo(link).itemLevel` (already gathered as `c.itemLevel`).
- **Most valuable**: `NS.Client.ItemValue(link, count)` with setting `valueSource = "vendor" | "auction" | "disenchant"`
  (default `vendor`, the only one implemented now). `auction`/`disenchant` are adapter slots that fall back to vendor
  when no provider (Auctionator/TSM/DE lib) is registered. Tie: quality, then ilvl, then slot order.

### 6.3 Decision record (shape returned by `Rewards.Evaluate`)

```lua
-- RewardDecision
{
  tier    = "Q"|"1"|"2"|"3"|"4"|"5",
  action  = "recommend"|"auto",
  index   = <choice index the engine favours, always set unless pending>,
  choice  = <the Choice table>,
  pool    = <Choice list with per-item { wearable, wornIlvl, delta, tierHit, tie } for /qam why and the pre-pick UI>,
  pending = true  -- only while item data loads (unchanged retry logic)
}
```
`Automation.Choose` → `TakeReward` when `action == "auto"`, else `LeaveChoice`. `Glow` always glows `index`.

### 6.4 Pre-pick UI at accept time (new feature, Phase 6)

When a quest is **accepted** and its log rewards (`Rewards.LogSource(questID)`) evaluate to a `recommend` tier
(Q/1/4 by default), show a small frame listing the choices with the engine's glow, and let the player click one.
The pick is stored in `QuestAutomatorCharDB.prePicks[questID] = choiceIndex` (keyed by **itemID**, not index, so
reordering cannot misfire). At hand-in, a stored pre-pick turns the tier into `auto` for that quest. Pre-picks
are cleared on `QUEST_TURNED_IN` / `QUEST_REMOVED`. Frame is optional: `prePickUI = true` setting; `/qam pick`
re-opens it for the selected log quest.

### 6.5 Settings schema changes

Removed: `rewardMode`, `fallbackToValue`, `weapons`, `trinkets` (trinkets are tier 1; weapons flow through tiers).
Added: `tier1Action..tier5Action`, `weaponProficiency`, `valueSource`, `prePickUI`.
Kept: `manualQuality`. `InitDB` drops the removed keys. Slash: `/qam tier <1-5> recommend|auto`, `/qam value vendor|auction|disenchant`,
`/qam weaponskill learnable|usable`.

**Location (requirement):** all settings live in the integrated **Esc → Options → AddOns → QuestAutomator** panel
(`Settings.RegisterAddOnCategory`, as upstream `Settings.lua` already does; same API on Forever and Era 1.15).
No standalone options window. `/qam settings` and the minimap right-click → Settings open that panel.

### 6.6 Phases (continue numbering from §5)

#### Phase 5 — Priority engine
- [ ] `Rules.EQUIP_SLOTS`, `Client.WornItemLevel(equipLoc)`, `Client.ItemValue(link, count)` (vendor), `Client.HasWeaponSkill(subclass)` (Era; Forever researched).
- [ ] `Rewards.Classify(choices, player, settings)` → per-item `{ wearable, hardToValue, wornIlvl, delta }`; tooltip proc-line detection via `C_TooltipInfo` lines starting with `ITEM_SPELL_TRIGGER_ONUSE` / `ITEM_SPELL_TRIGGER_ONPROC` / `ITEM_SPELL_TRIGGER_ONEQUIP` **not** matching a stat format.
- [ ] `Rewards.Evaluate` rewritten to the tier table; returns `RewardDecision`; tie-break by `FitScore` weights.
- [ ] `Automation.Choose`, `Glow.Decide`, `Glow.Explain` (`/qam why` prints tier, per-item wearable/worn/delta), `Rewards.Describe/ReasonText` texts (both locales).
- [ ] Settings page: five tier dropdowns, weapon proficiency, value source; read-only class weight block.
- [ ] `InitDB` migration of removed keys; defaults per §6.1.

#### Phase 6 — Pre-pick UI
- [ ] On `QUEST_ACCEPTED`: evaluate log rewards; if `recommend`, open `QuestAutomatorPrePickFrame` (icons + names, glow on engine pick, click = store).
- [ ] `prePicks` storage, consumption at hand-in, cleanup events, `/qam pick`.

#### Phase 7 — Value providers (later)
- [ ] `auction` via Auctionator/TSM API if loaded; `disenchant` via a DE-value lib; both behind `Client.ItemValue`.

#### Phase 8 — Stat-priority veto (later, owner-driven)
- [ ] Per-class wanted-stat sets; an "upgrade" must carry ≥1 wanted stat; config UI to allow lesser armour classes.

## 7. Open questions

- Upstream license (Phase 0 blocker for pushing publicly; not for local work).
- Era `C_Item.GetItemStats` key names — if they are `ITEM_MOD_*_SHORT` the tooltip parser is only a fallback and Phase 2 strings matter less.
- Does the owner want the XP bar at all? (Default: yes, port it.)
- Forever: API for "does the character have weapon skill X" (`usable` mode) — research.
- Tier 2/3 band width ±2 ilvl: confirm, or make it a setting (`ilvlBand`, default 2)? Assumed: a setting.