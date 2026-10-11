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
| OPT-01 | AppServiceLifecycleCoordinator coalesces ChatView/AppRoot startup, separates view interest, HA auth and foreground | Instrument multi-session/HA-user-swap test; migrate all eligible independent service lifecycle hooks |
| OPT-02 | Model-local, invalidated registry lookup index; no O(N) fingerprint per read; rooms and devices by IDs | Compare snapshot semantics on HA fake; incremental per-room presentation update; SwiftUI profiling |
| OPT-03 | Per-entity command serial lanes, explicit coalescing for safe absolute setpoints, no automatic replay; state-revision-aware optimistic updates | Integrate remaining Fire TV/cover/other adapters where appropriate; failure receipts, connectivity test matrix |
| OPT-04 | Bounded RAM-only ImageIO thumbnail cache; clears on chat reset/user forget; failed draft preserved | Video poster/player lifecycle, full outbox retry semantics, memory profiling and E2EE regression |
| OPT-05 | SingleFlightRequestScheduler; Runner status refresh integrated with auth-configuration revision fencing | Owner and Factory integration without cross-principal cache; TTL/backoff and conditional refresh |
| OPT-06 | Not migrated | Cold/warm start profiling; safe deferred initialization without delayed auth/UI |
| OPT-07 | Not migrated | Normalized indexed search; correctness under renames/state changes; warm result benchmark |
| OPT-08 | Not migrated | Jarvis/recording/audio coordination; verify AVAudioSession main-thread warning on iOS 27 |
| OPT-09 | Not migrated | Player view-state consolidation; Fire TV/Apple TV/Denon/PS5 capability & regression matrix |
| OPT-10 | Not migrated | Selective presentation stores; check Instruments render invalidations and visual goldens |
| OPT-11 | Not migrated | WireGuard status notifications and foreground/route lifecycle, signed capability parity |
| OPT-12 | Not migrated | Per-profile custom dashboard reorder and secure persistence; migration tests |
| OPT-13 | Not migrated | Safe Siri/App Intents navigation, confirmation/security policies, extension support |
| OPT-14 | Optional Instruments signposts for HA connect/flush/index and Chat.Send; strict comparable p50/p95 report utility with isolated synthetic *math-only* tests | **Real device/simulator Instruments baseline not measured**; expanded scenarios and gated comparable report |

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

**Compile gate not yet executed on this commit**. Last Xcode result from parent PR #4 was red due to the unscrolled LazyVStack accessibility test plus a 600-second failure-diagnostics hang. The current branch contains source fixes and hard process-group time budgets, but neither fix is accepted before a deliberately scoped targeted Xcode run and artifact verification. Do not call the 14 optimization program complete before remaining rows and G1–G6 are proven.
