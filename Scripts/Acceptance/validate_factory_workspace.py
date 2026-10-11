#!/usr/bin/env python3
"""Portable guard for staged, app-only Factory workspace consolidation."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

contracts = read("Sources/Features/Owner/Factory/FactoryWorkspaceContracts.swift")
gateway = read("Sources/Features/Owner/Factory/FactoryMCPService.swift")
connection = read("Sources/Features/Owner/Factory/FactoryConnectionModel.swift")
coordinator = read("Sources/Features/Owner/Factory/FactoryWorkspaceCoordinator.swift")
runtime = read("Sources/Core/IOSNextRuntime.swift")
root = read("Sources/App/AppRootView.swift")
system = read("Sources/Features/SystemView.swift")
standalone = read("Sources/Features/Owner/Factory/FactoryStandaloneView.swift")
overview = read("Sources/Features/Owner/Factory/FactoryOverviewView.swift")
modules = read("Sources/Features/Owner/Factory/FactoryWorkspaceModulesView.swift")
admin = read("Sources/Features/AdminAreaView.swift")
tests = read("Tests/FactoryWorkspaceContractsTests.swift")
ui_tests = read("UITests/FactoryWorkspaceUITests.swift")

required = {
    "version unchanged": "MARKETING_VERSION: 1.6.2" in read("project.yml"),
    "build unchanged": "CURRENT_PROJECT_VERSION: 25" in read("project.yml"),
    "one shared workspace": "let factoryWorkspace: FactoryWorkspaceCoordinator" in runtime,
    "shared standalone model": "runtime.factoryWorkspace.connection" in standalone,
    "shared owner model": "runtime.factoryWorkspace.connection" in overview,
    "factory tool guard": "FactoryWorkspaceToolCatalog.isPermittedRead(name)" in gateway,
    "no generic write routing": 'static func mayExecute(_ name: String) -> Bool { false }' in contracts,
    "new tool discovery": 'available.contains(name)' in gateway,
    "fail-closed connection": 'guard hasRestorableSession, phase == .connected' in connection,
    "workspace version validation": 'version == "factory.workspace.v1"' in contracts,
    "stale by default": '?? true' in contracts,
    "app-only OAuth retained": 'iosnext://factory-oauth' in gateway,
    "no implicit overview fallback":
       'guard connection.phase == .connected else' in coordinator
       and 'if discoveredTools.contains("workspace_overview_get")' in coordinator
       and 'overview = nil // Compatibility adapter' not in coordinator
       and 'overview = nil\n            overviewError = nil // Compatibility adapter remains available.' in coordinator,
    "central navigation":
       'FactoryWorkspaceModulesView(appModel: appModel)' in standalone
       and 'FactoryStandaloneView(appModel: appModel)' in system,
    "system single entry": 'system-factory-workspace' in system
       and 'system-live-operations' not in system and 'system-master-capabilities' not in system,
    "preconnect legacy hidden in production":
       'if ProcessInfo.processInfo.arguments.contains("--preconnect-ui-acceptance")' in root,
    "standalone live preserved": 'LiveOperationsView()' in modules,
    "standalone runner preserved": 'RunnerDashboardView(model: runtime.runnerModel)' in modules,
    "owner auth not bypassed":
       'AdminAreaView(appModel: appModel)' in modules
       and 'case .unlocked:' in admin
       and 'OwnerControlView(' in admin
       and 'lockedSurface(message:' in admin,
    "contract tests": 'testUnknownAndWriteToolsFailClosed' in tests,
    "new ui test": 'testUnifiedPreconnectionNavigationAndFailClosedState' in ui_tests,
}

for key, passed in required.items():
    print(f"FAI_PORTABLE_{key.upper().replace(' ', '_')}={'PASS' if passed else 'FAIL'}")
assert all(required.values()), "Factory workspace app-only guard failed"
print("FAI_PORTABLE=PASS")
