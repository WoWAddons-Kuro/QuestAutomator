-- Pure stat-profile tests (SPECS/STAT_PROFILES.md): no frames, no WoW API.
-- Run from workspace root: lua5.1 QuestAutomator/tests/stat_profiles.lua
local NS = {
	L = setmetatable({}, {__index = function(_, key) return key end}),
	RegisterEvent = function() end,
	Call = function() return nil end,
	SafeString = function(v) if type(v) == 'string' then return v end return nil end,
	SafeNumber = function(v) if type(v) == 'number' then return v end return nil end,
	SafeBool = function(v) return v == true end,
	Print = function() end,
	OnSettingsChanged = function() end,
	db = { statProfiles = {}, statProfileNextID = 1, statProfileMigrated = {} },
	chardb = {},
}
assert(loadfile('QuestAutomator/Rules.lua'))('QuestAutomator', NS)
local Rules = NS.Rules

-- Built-ins: every class has a leveling profile whose row IS Rules.WEIGHTS[class].
for class, row in pairs(Rules.WEIGHTS) do
	local list = Rules.BUILTIN_PROFILES[class]
	assert(list and #list >= 1 and list[1].id == class .. ':leveling' and list[1].builtin, class .. ' leveling built-in')
	for k, v in pairs(row) do assert(list[1].weights[k] == v, class .. ' leveling row mirrors WEIGHTS.' .. k) end
end
assert(Rules.BUILTIN_PROFILES.SHAMAN[1].name == 'Shaman Balanced Leveling')
assert(Rules.Profile('SHAMAN:leveling').class == 'SHAMAN' and Rules.Profile('NOPE:leveling') == nil)
-- Shaman ships four built-ins in slot order; a specialisation is the leveling row with
-- its deltas applied and nothing else changed (a COMPLETE row, readable as "leveling, but...").
local sh = Rules.BUILTIN_PROFILES.SHAMAN
assert(#sh == 4 and sh[2].id == 'SHAMAN:enhancement' and sh[3].id == 'SHAMAN:elemental' and sh[4].id == 'SHAMAN:restoration')
assert(sh[2].name == 'Shaman Enhancement' and sh[4].name == 'Shaman Restoration')
local enh, ele, res = sh[2].weights, sh[3].weights, sh[4].weights
assert(enh.STRENGTH == 1.2 and enh.INTELLECT == 0.3 and enh.MELEE_DPS == 4.0, 'enhancement: sharper melee, inherits weapon DPS')
assert(ele.INTELLECT == 1.4 and ele.SPELL_DAMAGE_DONE == 1.2 and ele.MELEE_DPS == 0.1 and ele.ATTACK_POWER == 0, 'elemental: caster, weapon DPS is a stat stick')
assert(res.SPELL_HEALING_DONE == 1.3 and res.MANA_REGENERATION == 1.3 and res.HIT_RATING == 0.1, 'restoration: healer')
assert(enh.ARMOR == 0.1 and ele.ARMOR == 0.1 and res.ARMOR == 0.1, 'keys not in a delta inherit the leveling value')
-- every class without deltas still has exactly its leveling row
assert(#Rules.BUILTIN_PROFILES.WARRIOR == 1 and #Rules.BUILTIN_PROFILES.PRIEST == 1)
-- built-in rows are complete: every EDITABLE_STATS key resolves to a number
for _, e in ipairs(Rules.EDITABLE_STATS) do assert(type(enh[e.key] or 0) == 'number') end
print('PASS built-in profiles: leveling row per class mirrors WEIGHTS; shaman ships 4 specs as deltas over it')

-- Selection: nothing set -> leveling default; a selected id of another class is ignored.
local sel = Rules.SelectedProfile('SHAMAN')
assert(sel.id == 'SHAMAN:leveling')
assert(Rules.SelectProfile('bogus') == false and NS.chardb.statProfileID == nil)
assert(Rules.SelectProfile('WARRIOR:leveling') == true)
assert(Rules.SelectedProfile('SHAMAN').id == 'SHAMAN:leveling', 'a warrior selection does not leak into a shaman lookup')
NS.chardb.statProfileID = nil
local w, source = Rules.Weights('SHAMAN')
assert(source == 'builtin' and w.STRENGTH == 1.0 and w.INTELLECT == 0.4, 'Weights reads the selected built-in')
assert(w.MELEE_DPS == 4.0, 'weapon pseudo-stats ride along')
print('PASS selection defaults to the class leveling profile; Weights reads it')

-- Fork: a complete copy, named Custom: <name>, forkedFrom the built-in, ids monotonic.
local c1 = Rules.ForkProfile('SHAMAN:leveling')
assert(c1 and c1.id == 'SHAMAN:custom:1' and not c1.builtin and c1.forkedFrom == 'SHAMAN:leveling')
assert(c1.name == 'Custom: Shaman Balanced Leveling')
assert(c1.weights.STRENGTH == 1.0 and c1.weights.MELEE_DPS == 4.0, 'fork copies the whole row')
assert(NS.db.statProfiles['SHAMAN:custom:1'] == c1 and NS.db.statProfileNextID == 2)
-- editing the fork does not touch the built-in
assert(Rules.SetProfileWeight(c1.id, 'INTELLECT', 1.4))
assert(c1.weights.INTELLECT == 1.4 and Rules.Profile('SHAMAN:leveling').weights.INTELLECT == 0.4)
assert(Rules.SetProfileWeight('SHAMAN:leveling', 'INTELLECT', 9) == false, 'built-ins are read-only')
assert(Rules.SetProfileWeight(c1.id, 'INTELLECT', 'x') == false, 'non-number rejected')
-- base weight for the grey placeholder
assert(Rules.ProfileBaseWeight(c1.id, 'INTELLECT') == 0.4 and Rules.ProfileBaseWeight('SHAMAN:leveling', 'INTELLECT') == 0.4)
print('PASS fork is a full copy; edits stay on the fork; built-ins immutable')

-- Selecting the fork changes what Weights returns for THIS character only.
assert(Rules.SelectProfile(c1.id))
w, source = Rules.Weights('SHAMAN')
assert(source == 'custom' and w.INTELLECT == 1.4)
-- a 0 weight is dropped from the scorer's view (absent == ignored)
assert(Rules.SetProfileWeight(c1.id, 'SPIRIT', 0))
assert(Rules.Weights('SHAMAN').SPIRIT == nil and c1.weights.SPIRIT == 0)
print('PASS selected custom profile drives Weights; zero weights are dropped')

-- Fork of a fork remembers the BUILT-IN it descends from.
local c2 = Rules.ForkProfile(c1.id, 'My Enhance')
assert(c2.id == 'SHAMAN:custom:2' and c2.name == 'My Enhance' and c2.forkedFrom == 'SHAMAN:leveling')
assert(c2.weights.INTELLECT == 1.4, 'copies the fork\'s current values')
-- Profiles(): built-ins first, then customs by id
local list = Rules.Profiles('SHAMAN')
assert(#list == 6 and list[1].id == 'SHAMAN:leveling' and list[4].id == 'SHAMAN:restoration' and list[5].id == c1.id and list[6].id == c2.id, 'four built-ins then customs by id')
assert(#Rules.Profiles('WARRIOR') == 1, 'customs are per class')
print('PASS fork-of-fork keeps the built-in ancestor; Profiles() ordering')

-- Rename: non-empty, unique within the class, custom only.
assert(Rules.RenameProfile(c1.id, '  Enhance PvE  ') and c1.name == 'Enhance PvE')
assert(Rules.RenameProfile(c2.id, 'enhance pve') == false, 'duplicate (case-insensitive) rejected')
assert(Rules.RenameProfile(c2.id, '') == false and Rules.RenameProfile('SHAMAN:leveling', 'x') == false)
-- FindProfile: exact beats prefix, case-insensitive
assert(Rules.FindProfile('SHAMAN', 'enhance pve') == c1)
assert(Rules.FindProfile('SHAMAN', 'my') == c2 and Rules.FindProfile('SHAMAN', 'shaman bal').id == 'SHAMAN:leveling')
assert(Rules.FindProfile('SHAMAN', 'zzz') == nil and Rules.FindProfile('SHAMAN', '') == nil)
print('PASS rename rules; FindProfile prefix matching')

-- Reset: weights := forked-from built-in's row.
assert(Rules.ResetProfile(c1.id) and c1.weights.INTELLECT == 0.4 and c1.weights.SPIRIT == 0.2)
assert(Rules.ResetProfile('SHAMAN:leveling') == false)
print('PASS reset restores the built-in row')

-- Delete: removes the store entry; a character on it falls back to the default.
assert(NS.chardb.statProfileID == c1.id)
assert(Rules.DeleteProfile(c1.id) and NS.db.statProfiles[c1.id] == nil and NS.chardb.statProfileID == nil)
assert(Rules.SelectedProfile('SHAMAN').id == 'SHAMAN:leveling')
assert(Rules.DeleteProfile('SHAMAN:leveling') == false and Rules.DeleteProfile(c1.id) == false)
-- a stale saved id (deleted elsewhere) resolves to the default without error
NS.chardb.statProfileID = 'SHAMAN:custom:99'
assert(Rules.SelectedProfile('SHAMAN').id == 'SHAMAN:leveling')
NS.chardb.statProfileID = nil
assert(Rules.DeleteProfile(c2.id))
assert(NS.db.statProfileNextID == 3, 'ids are never reused')
print('PASS delete; stale selection falls back; ids monotonic')

-- Migration: legacy per-cell overrides become one custom profile per class.
NS.db.statWeights = { SHAMAN = { INTELLECT = 1.4, SPIRIT = 0.6 }, MAGE = {}, DRUID = { AGILITY = 2.0 } }
Rules.MigrateLegacyWeights()
assert(NS.db.statWeights == nil, 'legacy table dropped')
local sham = Rules.Profile(NS.db.statProfileMigrated.SHAMAN)
assert(sham and sham.class == 'SHAMAN' and sham.weights.INTELLECT == 1.4 and sham.weights.SPIRIT == 0.6 and sham.weights.STRENGTH == 1.0,
	'shaman cells applied over the leveling row')
assert(NS.db.statProfileMigrated.MAGE == nil, 'an empty class row migrates nothing')
assert(Rules.Profile(NS.db.statProfileMigrated.DRUID).weights.AGILITY == 2.0)
Rules.MigrateLegacyWeights() -- idempotent when there is nothing left
assert(#Rules.Profiles('SHAMAN') == 5, 'four shaman built-ins + the migrated custom')
print('PASS legacy per-cell overrides migrate to one custom profile per class')

-- Player() still hands callers weights the same way.
NS.chardb.statProfileID = NS.db.statProfileMigrated.SHAMAN
NS.Call = function(path) if path == 'UnitClassBase' then return 'SHAMAN' elseif path == 'UnitLevel' then return 12 end return nil end
local player = Rules.Player()
assert(player.class == 'SHAMAN' and player.weights.INTELLECT == 1.4 and player.weightsSource == 'custom')
print('PASS Rules.Player() reads the selected profile')