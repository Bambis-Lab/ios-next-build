#!/usr/bin/env python3
"""Fail closed on app modifications outside the authorized Factory/Runner scope."""
import pathlib
import subprocess
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: validate_factory_scope.py <source_lock_sha>")
base = sys.argv[1]
changed = subprocess.check_output(
    ["git", "diff", "--name-only", f"{base}..HEAD"], text=True
).splitlines()
allowed = {
    "Sources/Features/Owner/OwnerControlView.swift",
    "Sources/Features/Owner/Shared/OwnerAppearance.swift",
    "Sources/Features/RunnerDashboardView.swift",
    "project.yml",
    "Info.plist",
    "Sources/Design/IOS27HomeComponents.swift",
    "Sources/Design/IOSNextComponents.swift",
    "Docs/Releases/1.5.0.md",
    "Docs/Releases/1.6.0.md",
    ".github/workflows/xcode-factory-1.5.0.yml",
    "Scripts/validate_factory_scope.py",
}
unauthorized = [
    path for path in changed
    if path not in allowed and not path.startswith("Sources/Features/Owner/Factory/")
]
if unauthorized:
    raise SystemExit("FACTORY_SCOPE=FAIL " + ", ".join(unauthorized))
if not changed:
    raise SystemExit("FACTORY_SCOPE=FAIL empty changes")
# Source strings are a deliberately conservative guard; Xcode compilation is authoritative.
root = pathlib.Path(".")
owner = (root / "Sources/Features/Owner/OwnerControlView.swift").read_text()
runner = (root / "Sources/Features/RunnerDashboardView.swift").read_text()
factory = (root / "Sources/Features/Owner/Factory/FactoryOverviewView.swift").read_text()
assert "FactoryOverviewView(ownerModel: ownerModel, runnerModel: runnerModel)" in owner
assert "FactoryAmbientBackground(kind: .runner)" in runner
assert "Factory-MCP-Registry" in factory and "FactoryCommandDeck" in factory
assert "func perform(" not in factory and "URLSession" not in factory
gateway = (root / "Sources/Features/Owner/Factory/FactoryMCPService.swift").read_text()
assert 'allowedTools:' in gateway and 'tools/call' in gateway and 'factory_status' in gateway
assert 'KeychainStore.save' in gateway and 'code_challenge_method' in gateway
assert 'SOURCE_WRITE' not in gateway and 'LIVE_WRITE' not in gateway
print("FACTORY_SCOPE=PASS", "files=" + str(len(changed)))
print("FACTORY_SOURCE_LOCK=" + base)
