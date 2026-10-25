# FAM12-04-FIX — Xcode 27 iPhone-only G99 launch isolation

Date: 2026-10-24. Source branch: `feature/iosnext-171-family-bootstrap` (Draft PR #6), based on `a3672277aa573b54b7092e9c6e3836a1bf64a155`.

## Observed failure
- Previous workflow: https://github.com/Bambis-Lab/ios-next-build/actions/runs/40131177778
- iPhone 18 Pro Max iOS 27. Source gate PASS; 171 Swift tests (1 skipped, 0 failures) PASS; Mika/Juli family UI PASS.
- Separate `testAccessibilityCoreScreenRenders` startup probe PASS (19.035 s).
- Later G99 10-case matrix: the **same test** failed in `XCUIApplication.launch()` after 139.854 s with `Failed to launch ... via Xcode: Timed out while launching application via Xcode.`. Other nine mandatory tests passed. Separate genuine Dynamic Type/Increase Contrast tests never began.
- There is no proven Accessibility assertion or app crash; the launch timeout indicates XCTest/CoreSimulator state uncertainty. Do not suppress the test or hide failed assertions.

## Targeted fix
1. In G99 test helpers, own the created XCUIApplication before `launch()`; tear down a running app even if `launch()` throws/fails. This applies only to UI acceptance test fixture, not production.
2. After first isolated startup probe, explicitly terminate the test app and confirm CoreSimulator boot status before the 10-case matrix.
3. Save the primary test result and logs; classify only **one exact Xcode launch-timeout** with zero assertion errors as infrastructure retryable. In that single case, terminate/prewarm and re-run all ten mandatory tests once; preserve both runs. Never retry a functional test failure.
4. Require exactly all ten listed G99 selectors and terminal `TEST EXECUTE SUCCEEDED`; preserve independent Dynamic Type / Increase Contrast tests and both screenshotted artefacts.
5. Add offline regression checks of strict log parsing to source CI. No loosened family authorization, E2EE, Xcode test gates, or production HA access.

## Release controls
- No main merges, no live HA/Factory operations, no SideStore release.
- `FAM11_STAGING_E2E_PASS` stays unset. A green synthetic/visual iPhone suite is not actual isolated HA+real iPhone E2E.
- All real terminal CI runs, required screenshot captures, and any failures must be reported after GitHub Actions finishes. No automatic claim of PASS.
