#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, shutil, subprocess, sys
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
dest = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else repo / '.runtime-stage'
head = subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'], text=True).strip()
if subprocess.check_output(['git','-C',str(repo),'status','--porcelain'], text=True).strip():
    raise SystemExit('refusing to stage from a dirty source tree')
source_service = repo / 'Backend' / 'runner_service' / 'service.py'
source_pkg = repo / 'Backend' / 'commander_live'
if dest.exists(): shutil.rmtree(dest)
dest.mkdir(parents=True)
shutil.copy2(source_service, dest / 'service.py')
shutil.copytree(source_pkg, dest / 'commander_live')
files = {}
for p in sorted(dest.rglob('*')):
    if p.is_file(): files[str(p.relative_to(dest))] = hashlib.sha256(p.read_bytes()).hexdigest()
manifest = {'schema':'iosnext.runtime-provenance/v1','repository':'Bambis-Lab/ios-next','source_commit':head,'files':files}
(dest / 'runtime-provenance.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
print(dest / 'runtime-provenance.json')
