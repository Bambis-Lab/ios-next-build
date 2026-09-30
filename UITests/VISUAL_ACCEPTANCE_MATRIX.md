# Native iOS Visual Acceptance Matrix — Phase 1

Inventory source product HEAD: `9bafb7bb818109cdcade6e40f7d6ce2dda38c678`

This matrix is rebuilt from the current product source. Legacy XCUITest grouping and run `35295372707` are reference evidence only.

## Phase gate

Phase 1 defines and statically validates the matrix only. It must not start final Xcode 27/iPhone 18 Pro Max acceptance, final card-catalog execution, final video acceptance, or Library finalization.

## Current product inventory

- Root states: connection landing, connection setup sheet, connected shell, reconnect overlay.
- Adaptive shell: 5 tabs (`home`, `rooms`, `chat`, `media`, `system`); TabView compact, NavigationSplitView regular.
- Acceptance surfaces: home, rooms, chat, media, system, light detail, media detail, owner, wireguard.
- Management surfaces: scenes, runner, diagnostics; hidden Owner entry is product behavior but not the acceptance entry path.
- Accessibility: Dynamic Type XXXL, Reduce Motion, Reduce Transparency, Increase Contrast.
- Devices/orientation: iPhone 18 Pro Max, iPad portrait, iPad landscape.
- Live HA catalog: 12 card types / 3 pages. Animation: 8 settled stages + full ordered sequence. Cold launch: normal no-test-argument launch.

## Scenario counts

- `accessibility`: 4
- `animation-sequence`: 1
- `animation-stage`: 8
- `card-catalog`: 3
- `cold-launch`: 1
- `detail`: 2
- `interaction`: 2
- `navigation`: 7
- `orientation`: 1
- `primary-screen`: 5
- `safe-state`: 3
- `state`: 1
- **Total stable scenario IDs: 38**

## Scenario contract

Every JSON scenario defines stable ID, category/surface/entry, preconditions, action, expected stable state, evidence type, variants, retry policy, failure classification, dependencies and notes.

## Legacy classification

- `testPrimaryProductScreensRenderLightAndDark` → **decomposed** → SHELL-001..005, DETAIL-001..002, OWNER-001, WG-001 — monolithic capture hid per-surface failure ownership
- `testNativeTabNavigationAndMediaDetail` → **decomposed** → NAV-001..007, DETAIL-002 — mixed navigation/detail assertions and brittle SwiftUI element-type assumptions
- `testChatComposerInteraction` → **retained-concept** → CHAT-INT-001 — safe draft typing retained; send/network side effects excluded
- `testLightSliderInteraction` → **retained-concept** → LIGHT-INT-001 — bounded visibility policy replaces fixed hittability timing
- `testOwnerAndWireGuardSafeEntryStates` → **split** → OWNER-001, WG-001 — different persistent-state risks need separate ownership
- `testAccessibilityCoreScreenRenders` → **obsolete-aggregate** → A11Y-001..004 — generic aggregate duplicated explicit accessibility scenarios
- `testDynamicTypeAccessibilityState` → **normalized** → A11Y-001 — expanded target set and readability contract
- `testReduceMotionAccessibilityState` → **normalized** → A11Y-002 — explicit motion-sensitive targets
- `testReduceTransparencyAccessibilityState` → **normalized** → A11Y-003 — explicit glass/management/privileged targets
- `testIncreaseContrastAccessibilityState` → **normalized** → A11Y-004 — explicit contrast-sensitive targets
- `testIPadPortraitLandscapeCoreScreens` → **decomposed** → device variants on primary scenarios, ORIENT-001 — device/orientation is a dimension, not one aggregate case
- `Scripts/run_ui_acceptance_matrix.sh selection order` → **reference-only** → VisualAcceptanceMatrix.json — legacy execution order must not define inventory
- `run 35295372707` → **reference-evidence-only** → no direct replacement — historical failure informs failure classes only; it cannot define rebuilt matrix

## Explicit exclusions

- **real Home Assistant authentication/network connection** — live/auth/network gate; clean landing and preview modes only
- **real chat send, attachment upload, camera/photo/video transfer** — external relay/media side effects; composer visual interaction only
- **real light/media/cover/lock/scene Home Assistant service calls** — would mutate external state; render controls but do not execute services
- **Owner Face ID unlock/admin actions/token configuration** — auth/secret/admin mutation gate; safe not-configured state only
- **WireGuard import/connect/on-demand/remove** — device/network/keychain/system VPN mutation gate; safe not-configured state only
- **Runner health/pause/resume/restart/shutdown actions** — runtime/network mutation gate; safe entry state only
- **destructive forget-connection action** — credential/keychain mutation; excluded from visual acceptance
- **final simulator wave, final card catalog run, final video acceptance, Library upload** — explicitly prohibited in Phase 1; matrix definition only

## Execution rule

Future execution selects stable scenario IDs from `VisualAcceptanceMatrix.json`, never the legacy test-method order. Retries recover only listed transient classes; wrong-state/semantic failures stay visible.
