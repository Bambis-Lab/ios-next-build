# FAI — Factory Workspace consolidation (iOS-only)

**Source lock:** published iOS Next 1.6.2 Build 25, `Bambis-Lab/ios-next-build@7ccaa14c7b3739daa23a249321305cc80f2b2dbe`.
**Scope:** app source, app-side tests and isolated Xcode27 CI. No deploys, IPA release, Factory VM, HA instance, canonical private repository, token changes or backend writes.

## FAI-01 — Verified 1.6.2 feature inventory

The locked mirror has 110 Swift source files (48 Feature, 46 Core, 11 Design, 5 App); 9 pre-existing Swift XCTest files and 4 pre-existing UI test files.
The following migration map is grounded in existing Swift routes and client contracts:

| Old navigation / source | Model, transport | New Factory module | Cutover condition |
| --- | --- | --- | --- |
| Control Center / Owner Control | AdminControlModel, authenticated /v1/admin and /v2/admin | Owner, Projects & Operations | Owner role, device binding, tickets, backup, maintenance and release action parity |
| Master Platform | MasterDataPlaneSnapshot.compatibility(Owner+Runner) | Factory Data / CI & Projects | New canonical registry, CI-run details and provenance contracts |
| Master Runtime Live | LiveOperationsModel using /v1/operations WebSocket | Live Operations | Factory sequenced event stream and history parity |
| CommanderLiveDetail | RunnerControlModel /v1/live WebSocket | Runner & Live Operations | Complete runtime/runner-event parity |
| Runner Dashboard | RunnerControlClient /v1/status + restricted POST actions | Runner & Infrastructure | Runner telemetry plus equal or stronger action authorization |
| Master Zugriff | static MasterGovernanceSnapshot.sourceOnly | Factory Governance | Real server capabilities plus principal-specific privileges |
| Factory Standalone | FactoryConnectionModel + MCP OAuth | Factory Workspace (single entry) | One Keychain/OAuth source of truth |
| Factory Overview nested in Owner | *separate* FactoryConnectionModel before FAI | Same shared FactoryWorkspaceCoordinator | Current implementation reuses one model |
| Home Assistant, Media, Lights, Chat, Jarvis | Specialized Home Assistant and Chat services | Unchanged independent product functions | Never conflate Factory with Home Assistant |

## App-side implementation blocks

- **FAI-02:** `FactoryWorkspaceToolCatalog` explicitly enumerates existing and future read tools. `FactoryMCPService.readWorkspaceTool` requires both local allowlist and server `tools/list`. No arbitrary tool invocation or write routing.
- **FAI-03:** `IOSNextRuntime.factoryWorkspace.connection` is the single FactorySession model for both Standalone and Owner Factory. Production Keychain and OAuth PKCE remain unchanged.
- **FAI-04:** `FactoryWorkspaceCoordinator` owns optional typed `factory.workspace.v1` state, source provenance, failures and freshness. Missing future tools do not create fake live data.
- **FAI-05:** One *production* Factory route appears on the disconnected landing view and in the System tab. Historical UI screenshot routes remain only under `--preconnect-ui-acceptance`.
- **FAI-06:** Runner and Owner modules are reachable within Factory. Existing authenticated APIs remain the functional adapters until backend parity; no duplicated token logic.
- **FAI-07:** LiveOperationsView is accessible under Factory. Optional `factory.events.v1` history includes sequence-based deduplication, gap detection and cursor reset. The original Live WebSocket remains the live authority until backend support exists.
- **FAI-08:** Owner, Projects, Backups, Releases, Tickets, Chat diagnostics and Owner Security stay behind the original Owner session and device authorization. Factory OAuth does not confer Owner rights.
- **FAI-09:** `FactoryWorkspaceToolCatalog.mayExecute` denies all newly proposed generic Factory write tools. Existing Owner/Runner actions retain their pre-existing independent policy checks.
- **FAI-10:** Portable policy tests, Swift contract tests, disconnected UI tests and Xcode 27 CI; no merge or release without terminal PASS.

## Pending backend contracts (APP DOES NOT IMPLEMENT SERVER FEATURES)

The running Factory v0.5.4 currently exposes its known read tools but **not** verified `workspace_bootstrap_get`, `workspace_overview_get`, `events_history_list`, comprehensive CI/project/Owner modules, or the future operation lifecycle.
The app has contracts ready for negotiated availability. A full legacy-backend removal is **blocked on real backend parity** and specific Xcode regression evidence.

## Acceptance/rollback requirements

1. Swift client compiles and all existing Factory OAuth regression tests pass with ephemeral fixture credentials.
2. Contract tests reject unauthorized tools, unknown schema versions and missing provenance.
3. Unified production navigation is verified without any automatic factory login; old screenshot harness is unaffected.
4. Event tests prove sequence deduplication and fail-closed gaps.
5. Light/Dark iPhone/iPad, dynamic type and accessibility regressions are re-reviewed before release.
6. Keep SideStore 1.6.2 and its original source commit untouched as rollback. Any future version requires independent device IPA build and approval.

**Operational rule:** Do not delete compatibility adapters, create new user privileges or trigger live actions merely because a tool name appears in `tools/list`.
