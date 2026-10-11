# XB-05 post-acceptance visual polish (isolated stage)

Source: public sanitized `Bambis-Lab/ios-next-build`, branch `visual/ios-next-162-post-xb05-polish`. This branch was created from `xb05/acceptance-xcode27-56` to preserve the running 56-screenshot acceptance snapshot.

## Read-only UI adjustments

- Owner preconnection and Runner/Factory disconnected descriptions: increase secondary-text contrast using the adaptive primary color at ~80% opacity; keep existing layout and backgrounds.
- Owner locked/error/authenticating surfaces: provide an accessible persistent status note explaining that actions remain locked until device authentication and server-side authorization. No authentication or permissions logic changes.
- UITest assertion for the new note in the deterministic Owner locked visual fixture.

## Acceptance order

1. **Blocker:** Existing strict XB-05 run `38160154864` is still pending. Inspect terminal logs and 56 PNG artifacts; do not infer success from prior run `38147228536`.
2. Confirm no near-duplicate images in either appearance, and complete Factory credential regressions.
3. Only then run an isolated Xcode 27 UI test of **this** staged polish branch and inspect Light/Dark results, Dynamic Type and accessibility contrast.
4. Only after all gates pass consider producing an unsigned free-sideload IPA **candidate** (no distribution, resigning, publishing, deployment or release). Actual SideStore installation requires its separate signing step and is not covered by unsigned simulator screenshot tests.

The private canonical `Bambis-Lab/ios-next`, Factory, HA, live backends, signing secrets and existing installed IPA are untouched. No product PR merge is authorized by this staging work.
