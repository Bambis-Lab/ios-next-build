# B-06 – Xcode 27 iPhone XCTest startup stabilization

Branch: `fix/iosnext-164-dashboard-sliders-fix01-05`  
Baseline HEAD: `cfc1d59ff9ac02025098b020709c1754703eebf8`

## Last verified evidence

- [Targeted #38701482821](https://github.com/Bambis-Lab/ios-next-build/actions/runs/38701482821): the **first test** `testLightSliderInteraction` timed out in `XCUIApplication.launch()` after approximately 293 seconds; later `testLiveOperationsSafeEntryState` passed and the Media/Fire TV test navigated into the detail sheet.
- [B-05 #38704734876](https://github.com/Bambis-Lab/ios-next-build/actions/runs/38704734876): 2 capability unit tests and the full Media/Fire TV UI path **PASS**, with the iPhone simulator explicitly booted first.
- This is evidence of a first-launch failure pattern, **not proof** that the simulator boot caused it.

## Changes

1. Resolve the fixed iPhone 18 Pro Max / iOS 27 destination, then run existing `Scripts/Acceptance/boot_simulator.py` with bounded boot/bootstatus. Do not boot any iPad.
2. `xcodebuild build-for-testing` to materialize the app plus the XCTest runner once before XCTest starts.
3. `simctl install` and one controlled preview-mode `simctl launch` (only `--product-ui-test-screen=light`), capture an optional simulator screenshot, terminate preview app before XCTest. No live HA calls.
4. `xcodebuild test-without-building` with the exact generated `.xctestrun`. Retain the original three test selectors and the original XCTest assertions.
5. Preserve Build/Boot/Prewarm/Test logs and `.xcresult` on success or failure. Retain nonzero `xcodebuild` status; no retry-by-default.

## Gate

`B06_LAUNCH_PASS` requires `simctl bootstatus`, app install, prewarm process launch, and an XCTest launch reaching the first actual UI assertions **without an Xcode application-launch timeout**. `B06_BLOCK_B_PASS` additionally requires all three Block-B UI tests to pass. A slider-hittability failure is B-07, not a B-06 startup failure. These must be reported separately.

This workflow is targeted iPhone-only. **Do not dispatch G99**, run iPad, merge or release.
