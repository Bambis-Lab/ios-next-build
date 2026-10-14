# SL-01–SL-05 — iOS Next 1.6.4 Build 27 slider acceptance

Source baseline: `ba786f1e36ca8524ac79aef1a5e9993cf397bab2` (published 1.6.3 build 26).
Scope: UI slider state only. No backend, Factory, Home Assistant, release feed, or deployment changes.

## SL-01 source findings
- `MediaVolumeControl` and `MediaSeekControl` previously used a draft state only during `onEditingChanged`. A stale Home Assistant report immediately after finger-up could overwrite the chosen value.
- `NicoPrimaryLightTile` had the same gap.
- `LightControlSheet.syncFromEntity()` previously rewrote brightness and color temperature without checking whether a gesture was active.
- Existing service APIs remain unchanged: `media_player.volume_set`, `media_player.media_seek`, and `light.turn_on`.

## SL-02–SL-03 implementation
- Introduced `SliderValueReconciler`: local gesture ownership, pending device acknowledgement, tolerance-based confirmation, revision-gated settlement.
- Added protection to volume, seek, room brightness, light-sheet brightness, and light-sheet temperature.
- A two-second grace period prevents immediate rollback by stale device events. After it expires, the latest post-gesture device value may be restored. This is a UI policy, **not** proof of service success.
- Gesture starts invalidate older timer generations. Views cancel timers when dismissed.
- **Known limitation:** the reconciliation layer does not currently receive explicit service-call failure/success callbacks. If the backend never acknowledges, the slider can remain on the locally chosen value until a later device update. Do not claim full end-to-end confirmation.

## SL-04 regression coverage
- `SliderValueReconcilerTests` reproduces the Denon 9% -> 70% -> 7% race.
- Also checks active-gesture ownership, stale timeout generations, seek tolerance, no post-gesture report, and nonfinite input.
- Xcode 27 iPhone and iPad simulator tests are mandatory before marking the patch ready.

## SL-05 acceptance gates
1. Xcode 27 iPhone build and targeted slider unit tests pass.
2. Xcode 27 iPad build and targeted slider unit tests pass.
3. iPhone/iPad UI drag test moves volume, brightness, seek, and temperature slider thumbs.
4. Inject an old device report while dragging and after finger-up: the thumb must not snap back during the pending window.
5. Confirm actual Denon AVR behavior on the physical device with Home Assistant state/service events before declaring live-device parity.
6. **No SideStore release, no merge, no main writes.** Publication requires fresh explicit user approval.

Status: Implementation committed to feature branch; acceptance evidence must come from the actual CI run.
