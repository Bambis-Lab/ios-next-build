# IPH-00 / IPH-01 – iPhone-only CI scope and failure baseline

Date: 2026-10-15 (UTC). Repository: `Bambis-Lab/ios-next-build`.
Branch: `fix/iosnext-164-dashboard-sliders-fix01-05`.
Last verified branch baseline before this change: `ed0e422260a7c2f5d6a04deaecf051937ddc5272`.

## Scope and authorization

Current repair acceptance is **iPhone 18 Pro Max, iOS 27, portrait only**.
No iPad runner, iPad simulator, iPad orientation test or iPad screenshot belongs in this phase.
This is a **test/CI-scope decision**, not a removal of iPadOS app support. No production UI
or runtime change is authorized in Block A.

## IPH-00 – workflow inventory and actions

- `.github/workflows/slider-164-xcode27.yml`: originally invoked `xcode27-iphone`
  and `xcode27-ipad` on every push to this branch. Remove **the entire iPad job**
  and its iPad artifact; keep the existing `source-check` and `xcode27-iphone`.
- `.github/workflows/g99-ios-next-164-acceptance.yml`: originally used
  `matrix.device: [iphone, ipad]`, selected an iPad simulator and included
  `testIPadPortraitLandscapeCoreScreens` in both UI passes. Replace the matrix
  with a single iPhone-18-Pro-Max destination; remove the iPad-only selection;
  keep all other UI tests. Disable `push` triggers during repair, retaining
  manual `workflow_dispatch` for the eventual G99-F after separate verification.
- Other workflows currently scoped to other feature branches (such as
  `nico-factory-performance-xcode27.yml`) or manual dispatch are **not triggered**
  by a normal push to this branch. They are outside Block A's change scope.
  Do not manually dispatch their iPad jobs.

## IPH-01 – frozen observed iPhone failure baseline

Source: GitHub Actions [G99 #38663173317](https://github.com/Bambis-Lab/ios-next-build/actions/runs/38663173317),
`g99-ui (iphone)`, job `116190792126`, Xcode 27 `UI-light` execution.
**12 tests executed, 9 failures, 3 passed**. The workflow stopped before its
second outer `dark` pass; `testPrimaryProductScreensRenderLightAndDark`
itself passed in this light-pass job, running its own light/dark captures.
Assertions below are the *observed first failures*, not all proven causes.

| Test / observed failure | Source line (original) | Status / subsequent work |
|---|---|---|
| `testDynamicTypeAccessibilityState`: missing `dynamicTypeAccessibility=true` | `UITests/IOSNextUITests.swift:384` | FAILED – real simulator accessibility state not proven; IPH-05 |
| `testIncreaseContrastAccessibilityState`: missing `increasedContrast=true` | `:402` | FAILED – real simulator state not proven; IPH-05 |
| `testIPadPortraitLandscapeCoreScreens`: orientation 3 did not settle, took 366.882 s | `:224` | FAILED – **confirmed wrong device/scope**; remove from iPhone G99; IPH-00 |
| `testLightSliderInteraction`: slider not hittable after four global swipes | `:173` | FAILED – element exists; scroll/interception root cause still to determine; IPH-04 |
| `testLiveOperationsSafeEntryState`: `system-live-operations` missing | `:163` | FAILED – selector not in current `SystemView`; product routing to resolve; IPH-03 |
| `testNativeTabNavigationAndMediaDetail`: `media-active-summary` not visible after media tab action | `:289` | FAILED – navigation or presentation cause unproven; IPH-02 |
| `testOwnerAndWireGuardSafeEntryStates`: expected `Control Center nicht eingerichtet` not found | `:344` | FAILED – current `AdminAreaView` exposes `control-center-unconfigured` + setup action; IPH-03 |
| `testReduceMotionAccessibilityState`: missing `reduceMotion=true` | `:390` | FAILED – real simulator state not proven; IPH-05 |
| `testReduceTransparencyAccessibilityState`: missing `reduceTransparency=true` | `:396` | FAILED – real simulator state not proven; IPH-05 |

**Passing iPhone UI tests in that run:**
- `testAccessibilityCoreScreenRenders`
- `testChatComposerInteraction`
- `testPrimaryProductScreensRenderLightAndDark`

**Prior unit results:** `g99-a` and `g99-b` in run #38663173317 were green
at commit `d6dbd67d`; those passes do **not** certify subsequent commits.

**Most recent isolated slider reference:** [#38673731603](https://github.com/Bambis-Lab/ios-next-build/actions/runs/38673731603)
at `ed0e422260a7c2f5d6a04deaecf051937ddc5272`, `source-check`, `xcode27-iphone`, and (historically) `xcode27-ipad`
passed. The iPad result is historical only; **not a required gate going forward**.

## Important regression warning from prior Accessibility patch

The test arguments `--product-ui-test-reduce-motion`,
`--product-ui-test-reduce-transparency`,
`--product-ui-test-increase-contrast`, and
`--product-ui-test-dynamic-type` have been added to some test launches,
but they do not currently set the corresponding read-only SwiftUI environment
values. Attempting to write `\.accessibilityReduceMotion`,
`\.accessibilityReduceTransparency` or `\.colorSchemeContrast`
using `.environment` in `AppRootView` caused Xcode compile errors;
that code was removed in `ed0e422260a7c2f5d6a04deaecf051937ddc5272`. **Do not reintroduce it.**
IPH-05 must verify supported system-state configuration and real UI behavior.

## Exit criteria and next action

- New branch push triggers **only iPhone slider acceptance**, no iPad test job.
- G99 is manual-only, iPhone destination and no iPad UI-test selector.
- The nine observed UI failures above are registered with evidence and owner phase.
- No full G99 has been started as part of Block A.
- Block A completion is a CI-scope/baseline milestone, **not product READY**.
- Next implementation phases: IPH-02…IPH-06, VER-00…VER-03, then G99-F only when ready.
