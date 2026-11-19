# iOS Next 1.8.0 – V6.3 duration contract
Approved 2026-11-19. Supersedes only the continuous media duration in earlier V6 acceptance plans.
| Stage | Seconds | Frames per sender | Two-sender total |
|---|---:|---:|---:|
| Short | 30 | 1500 | 3000 |
| Functional | 120 | 6000 | 12000 |
| Sustained | 300 | 15000 | 30000 |

50 frames/s per sender, excluding authenticated rendezvous frame. Each fresh isolated run uses two independent iPhone 18 Pro Max iOS 27 simulators, exact destination evidence and original XCResult. The 30/120/300 jobs are sequential gates. No 600 or 1800 second stage in the current workflow; historical commits and artifacts are retained. Maximum continuous group audio stage also 300 seconds, with 2/3/5-client security tests still required. G03 additionally requires reconnect, real token renewal behavior, replay/key management, revocation, audio routing, accessibility and performance. Synthetic WSS passing does not prove physical audio quality, production HA, or stability beyond five minutes. G04 remains blocked until G03; no release before all gates.
