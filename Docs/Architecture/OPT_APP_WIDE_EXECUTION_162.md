# iOS Next 1.6.2 — App-wide optimization execution register

## Scope, provenance and safety

- Source lock: `Bambis-Lab/ios-next-build@6050ad0295ea5a7fda422a123426f1e2c9634baa` (draft PR #4).
- Work branch: `feature/ios-next-opt-01-14-foundation-162`.
- Scope: iOS app source, isolated tests and app-owned CI workflow only.
- Never modify live Home Assistant, Factory VM, Owner/Runner backend, the canonical private repo, SideStore feed, or public IPA.
- This is a staged source implementation, **not a verified release**. Portable acceptance never substitutes for Swift/Xcode compilation or Instruments baselines.
- No Xcode job is dispatched automatically by commits on this work branch. Xcode can be started only by an explicit acceptance workflow dispatch after source review and time-budget approval.

## Block 0 — FIX (current status)

| ID | Source implementation | Runtime proof |
| --- | --- | --- |
| FIX-01 | LazyVStack accessibility test now scrolls, checks hittability and attaches hierarchy on failure | **Awaiting Xcode target test** |
| FIX-02 | App-local Xcode workflow uploads `.xcresult` with `if: always()` | **Awaiting deliberate failing-test verification** |
| FIX-03 | Compile and UI test phases separated; one iPhone build used for selected tests | **Awaiting Xcode measurement** |
| FIX-04 | Process-group watchdog limits compilation (660s), UI (240s), boot (105s/90s); job max 18 min | **Awaiting Xcode verification** |
| FIX-05 | Push triggers portable only; manual `workflow_dispatch` required for Xcode | GitHub portable runs have demonstrated skipped Xcode job |
| FIX-06 | RGB/white/temp/effects share latest-value UI lane, HA entity actions serial, segment actions share lane, HA state revision gate | Source/portable validated; **Xcode and integration tests outstanding** |

## App-wide OPT register

| ID | Current source implementation | Remaining requirements |
| --- | --- | --- |
| OPT-01 | AppServiceLifecycleCoordinator coalesces AppRoot/ChatView startup; ChatModel now fences direct starts, configuration generations, stop/cancel and outgoing sends | Xcode concurrency test, multi-session/HA-user-swap proof; lifecycle for other services remains partly local |
| OPT-02 | Model-owned registry cache invalidated on device/registry edits; duplicate entity/device rows are normalized; ID/domain indexes and indexed room snapshots | HA fake tests for area/device changes; incremental per-room snapshots and Instruments profile |
| OPT-03 | Typed command results (executed/superseded/cancelled/failed/outcomeUnknown), per-entity FIFO lanes, safe queued-value replacement, connect-generation and state-revision fencing; Fire TV calls use same lane | Real HA transport test for late send/unknown outcome; verify all toggle/scene/cover/player adapters and visible failure receipt |
| OPT-04 | RAM-only ImageIO thumbnails with 24 MiB cache cap and off-main decoding; draft survives failed send; identity-generation fences prevent cross-account completion; recording/playback audio leases | Video poster/player lifecycle, fully specified retry/outbox contract, memory-pressure and E2EE regression tests |
| OPT-05 | Runner status single-flight + configuration generation; Owner V2 refreshes coalesced and session-fenced; event responses fenced; Factory MCP tool list cache only while session exists | Backoff/TTL/conditional requests and measured request counts still needed; no shared credentials/cache across security domains |
| OPT-06 | Runner, Live and Factory models initialized lazily on feature access; runtime initialization signposted | Real cold/warm start baseline, ensure first-use latency remains acceptable |
| OPT-07 | Debounced GlobalSearchIndex with pre-normalized/pre-sorted fields; batched HA state revision invalidates results | Xcode correctness test, large-registry search p50/p95 and memory profile |
| OPT-08 | AppAudioCoordinator lease arbitration integrates Jarvis, chat playback and microphone recorder; recorder removes tap and releases lease on stop/failure | Confirm all TTS/interrupt/audio-route paths and the iOS 27 AVAudioSession warning on actual supported devices |
| OPT-09 | MediaPresentationSnapshot groups player state once per HA revision; MediaView and player lookups use shared index | Cross-device capability/interactions test for Fire TV/Apple TV/Denon/PS5, no regression in seek/volume/mute |
| OPT-10 | RoomPresentationSnapshot indexed by area; media snapshot and signposts are present; dashboard uses stable presentation options | Complete Home/Room/Media/SystemHealth store migration remains open; Instruments redraw invalidation proof |
| OPT-11 | WireGuard observes NEVPNStatusDidChange; programmatic state restoration no longer re-triggers on-demand toggle; removal clears observer | Test manager reload, route/background and real NetworkExtension state transitions |
| OPT-12 | Local per-profile dashboard tile visibility/order UI with reset and persistence | Verify profile identity stability and migration across profile renames/resets, VoiceOver acceptance |
| OPT-13 | AppIntents for opening Home, Rooms and Media; tab request consumed on launch/foreground; no privileged Factory write intents added | Xcode App Shortcuts metadata/phrase validation and end-to-end Siri invocation |
| OPT-14 | Opt-in privacy-safe signposts + strict environment-matched p50/p95 comparator; Python comparator unit fixtures do not claim app measurements | **Real baseline and candidate measurement absent**; need an explicit bounded Xcode/Instruments run and archived comparable reports |

## Verification ladder (do not skip)

1. **G0**: Portable contract tests + Python comparator unit tests, branch-source static checks.
2. **G1**: Xcode 27 compiler gate with 660s subprocess watchdog, one source lock.
3. **G2**: Swift unit tests (device queue, chat draft, Factory).
4. **G3**: Targeted red Nico accessibility test; hierarchy and screenshots even on failure, max 240s.
5. **G4**: Separate iPhone/iPad Light/Dark/large text/Reduce Motion, real interactions.
6. **G5**: Real Instruments baseline and candidate p50/p95, CPU/RSS/network plus E2EE and security.
7. **G6**: Full Xcode acceptance on release candidate, explicit approval for IPA/SideStore publication.

Manual smoke must pass before full visual; never upgrade evidence from portable to Xcode proof. A rejected or exceeded budget leaves draft PR unmerged.

## Nonnegotiable behavioral and security invariants

- No Owner, Runner, Factory write authority gained from UI routing.
- No cross-principal request cache or Keychain token mixing.
- Chat images are downsampled only in RAM; no plaintext image/video disk cache.
- No silent retries for toggle, scene, lock, shutdown or similar side effects.
- No stale local optimistic snapshots may overwrite newer HA state events.
- No state invented for disconnected devices, missing capabilities or unknown Factory tools.
- Existing SideStore 1.6.2 Build 25 stays immutable until separately authorized release.

## Next evidence needed

**Compile gate not yet executed on this branch.** The previous portable red check was a stale static expectation for the old color-queue API; it is now aligned to the actual generation-bound `QueuedLightColorCommand` contract. The latest portable run after both the color-validator correction and Owner/Factory stale-response fixes passed, and Xcode was skipped by design. The earlier parent PR #4 Xcode failure (unscrolled LazyVStack accessibility test + 600-second diagnostic hang) remains unverified on this new source head. Do not call the 14 optimization program complete until G1–G6 have independent evidence.
