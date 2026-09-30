#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
project = (ROOT / "project.yml").read_text(encoding="utf-8")
codemagic = (ROOT / "codemagic.yaml").read_text(encoding="utf-8")

def one(pattern: str, text: str, label: str) -> str:
    values = re.findall(pattern, text, flags=re.MULTILINE)
    if len(values) != 1:
        raise SystemExit(f"{label}: expected one value, found {values}")
    return values[0]

project_version = one(r"^\s*MARKETING_VERSION:\s*([^\s]+)\s*$", project, "project version")
project_build = one(r"^\s*CURRENT_PROJECT_VERSION:\s*([^\s]+)\s*$", project, "project build")
expected_version = one(r'^\s*EXPECTED_VERSION:\s*"([^"]+)"\s*$', codemagic, "Codemagic version")
expected_build = one(r'^\s*EXPECTED_BUILD:\s*"([^"]+)"\s*$', codemagic, "Codemagic build")
source_base = one(r'^\s*SOURCE_BASE_SHA:\s*"([0-9a-f]{40})"\s*$', codemagic, "source base")

if (project_version, project_build) != (expected_version, expected_build):
    raise SystemExit(f"release metadata mismatch: project={project_version}/{project_build} codemagic={expected_version}/{expected_build}")

notes_path = ROOT / "Docs" / "Releases" / f"{expected_version}.md"
if not notes_path.is_file():
    raise SystemExit(f"missing SideStore What’s New notes: {notes_path.relative_to(ROOT)}")
notes = notes_path.read_text(encoding="utf-8").strip()
if not notes or not any(line.lstrip().startswith("-") for line in notes.splitlines()):
    raise SystemExit(f"SideStore What’s New notes must contain bullet points: {notes_path.relative_to(ROOT)}")

provenance = json.loads((ROOT / "manifests/migration-provenance.json").read_text(encoding="utf-8"))
release_source = provenance.get("release_source_base", {})
if release_source.get("commit") != source_base:
    raise SystemExit(f"release source base provenance mismatch: {release_source.get('commit')} != {source_base}")
if release_source.get("verified_ancestor_of_primary_source") is not True:
    raise SystemExit("release source base ancestry is not verified in migration provenance")
if release_source.get("verified_in_source_repository") != "nicofroeba16-cell/iOS-App":
    raise SystemExit("release source base repository provenance mismatch")
print(f"Release metadata valid: {project_version} build {project_build}, source base {source_base} (provenance-verified)")
