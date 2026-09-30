#!/usr/bin/env bash
set -euo pipefail

: "${CM_COMMIT:?CM_COMMIT is required}"
: "${EXPECTED_VERSION:?EXPECTED_VERSION is required}"
: "${EXPECTED_BUILD:?EXPECTED_BUILD is required}"

cp project.yml project.free.yml
python3 - <<'PY'
from pathlib import Path
p = Path('project.free.yml')
s = p.read_text()
old_ent = '        CODE_SIGN_ENTITLEMENTS: Sources/Resources/IOSNext.entitlements\n'
if old_ent not in s:
    raise SystemExit('Expected main-app CODE_SIGN_ENTITLEMENTS not found')
s = s.replace(old_ent, '        CODE_SIGN_ENTITLEMENTS: ""\n        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) IOSNEXT_FREE_SIDELOAD"\n', 1)
old_dep = """    dependencies:\n      - target: IOSNextPacketTunnel\n        embed: true\n        link: false\n"""
if old_dep not in s:
    raise SystemExit('Expected IOSNextPacketTunnel embed dependency not found')
s = s.replace(old_dep, '', 1)
p.write_text(s)
PY
python3 - <<'PY'
import json, os
from pathlib import Path
version = os.environ['EXPECTED_VERSION']
notes_path = Path('Docs/Releases') / f'{version}.md'
if not notes_path.is_file():
    raise SystemExit(f'Missing SideStore What’s New notes: {notes_path}')
release_notes = notes_path.read_text(encoding='utf-8').strip()
payload = {
    'source_commit': os.environ['CM_COMMIT'].strip(),
    'version': version,
    'build': os.environ['EXPECTED_BUILD'],
    'build_flavor': 'free-sideload',
    'release_notes_markdown': release_notes,
}
Path('Sources/Resources/build_info.json').write_text(json.dumps(payload, sort_keys=True, separators=(',', ':')) + '\n')
PY
xcodegen generate --spec project.free.yml
printf '%s\n' "$CM_COMMIT" > .free-sideload-ready
