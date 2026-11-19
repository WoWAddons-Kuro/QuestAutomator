"""Verify restored runtime against the ZIP, allowing only enumerated UI/name edits."""
from pathlib import Path
import hashlib
import zipfile

root = Path(__file__).resolve().parents[1]
archive = root.parent / 'SmartQuestAutomation_forkbase.zip'

def rename(text):
    for old, new in [
        ('SmartQuestAutomation', 'QuestAutomator'),
        ('SMARTQUESTAUTOMATION', 'QUESTAUTOMATOR'),
        ('Smart Quest Automation', 'Quest Automator'),
        ('Smart Quest', 'Quest Automator'),
        ('/smartquest', '/questautomator'),
        ('/sqa', '/qam'),
    ]:
        text = text.replace(old, new)
    return text

with zipfile.ZipFile(archive) as source:
    for name in ['Automation.lua', 'Rewards.lua', 'Rules.lua', 'Glow.lua', 'XPBar.lua', 'Core.lua']:
        entry = next(path for path in source.namelist() if path.endswith('/' + name))
        expected = rename(source.read(entry).decode('utf-8-sig').replace('\r\n', '\n'))
        if name == 'Automation.lua':
            old = 'questID and NS.SafeBool(info.isComplete) and Auto.MayTurnIn'
            new = 'questID and (NS.SafeBool(info.isComplete) or NS.SafeBool(NS.Call("IsQuestComplete", questID))) and Auto.MayTurnIn'
            assert expected.count(old) == 1
            expected = expected.replace(old, new)
        if name == 'Rewards.lua':
            old = 'function Rewards.Describe(decision)\n\tlocal c = decision.choice\n\tif not c then return "" end\n'
            assert expected.count(old) == 1
            expected = expected.replace(old, old + '\tif decision.reason == "prepick" then return L["your pre-pick"] end\n')
        if name == 'Core.lua':
            edits = [
                ('\t\tNS.SetFlag("enabled", "", L["Automation"])\n\tend\nend\n',
                 '\t\tif NS.PrePick then NS.PrePick.OpenAny() end\n\tend\nend\n'),
                ('\tGameTooltip:AddLine(L["Left-click: switch on or off. Right-click: settings."], 0.8, 0.8, 0.8)',
                 '\tGameTooltip:AddLine(L["Left-click: pick window. Right-click: settings."], 0.8, 0.8, 0.8)'),
                ('\telseif cmd == "settings" or cmd == "options" or cmd == "config" then',
                 '\telseif cmd == "pick" then\n\t\tif NS.PrePick then NS.PrePick.Command(rest) end\n\telseif cmd == "prepick" then\n\t\tNS.SetFlag("prePickUI", rest, L["Ask me when I accept a quest"])\n\telseif cmd == "settings" or cmd == "options" or cmd == "config" then'),
                ('\tNS.Print(L["/qam settings - open the settings page"])',
                 '\tNS.Print(L["/qam settings - open the settings page"])\n\tNS.Print(L["/qam prepick on|off - ask when a quest is accepted; /qam pick - open the pick window for the selected quest"])'),
            ]
            for old, new in edits:
                assert expected.count(old) == 1, (name, old)
                expected = expected.replace(old, new)
        actual = (root / name).read_text(encoding='utf-8-sig')
        if name == 'Automation.lua':
            # Auto.Choose is the deliberately extracted boundary, tested behaviourally
            # by turn_in_resolver.lua and ui_smoke.lua. All surrounding code must match.
            start_marker = 'function Auto.Choose(questID, attempt)'
            end_marker = 'function Auto.Retry(questID, attempt)'
            assert actual.count(start_marker) == expected.count(start_marker) == 1
            assert actual.count(end_marker) == expected.count(end_marker) == 1
            actual_start, actual_end = actual.index(start_marker), actual.index(end_marker)
            expected_start, expected_end = expected.index(start_marker), expected.index(end_marker)
            integration = actual[actual_start:actual_end]
            assert hashlib.sha256(integration.encode()).hexdigest() == '9708fc9d835dc054aa3e0adbcfc62bd57023e3a955288817f9d902a3e5967168', 'Auto.Choose changed since owner-confirmed resolver checkpoint'
            assert 'NS.TurnInResolver' in integration and 'Rewards.Evaluate(' not in integration
            expected = expected[:expected_start] + integration + expected[expected_end:]
        assert actual == expected, f'{name}: unexpected change from archived runtime'
        if name == 'Core.lua':
            print('PASS Core.lua: naming + enumerated UI entry points only')
        elif name == 'Automation.lua':
            print('PASS Automation.lua: all functions unchanged except verified gossip fallback and tested Auto.Choose resolver boundary')
        elif name == 'Rewards.lua':
            print('PASS Rewards.lua: naming + pre-pick description only; original scoring unchanged')
        else:
            print(f'PASS {name}: naming only')

for removed in ['Client.lua', 'Engine.lua', 'PrePick.lua', 'RewardSelectionPolicy.lua']:
    assert not (root / removed).exists(), f'Obsolete runtime remains: {removed}'
toc = (root / 'QuestAutomator.toc').read_text(encoding='utf-8-sig')
for line in toc.splitlines():
    if line and not line.startswith('#'):
        assert (root / line.replace('\\', '/')).is_file(), f'Missing TOC file: {line}'
for path in list((root / 'UI').glob('*.lua')) + [root / 'Settings.lua']:
    text = path.read_text(encoding='utf-8-sig')
    assert 'NS.Client' not in text and 'NS.Engine' not in text, path
    assert 'NS.Auto.' not in text, f'UI modifies automation boundary: {path}'
print('PASS TOC and removed-adapter dependency checks')