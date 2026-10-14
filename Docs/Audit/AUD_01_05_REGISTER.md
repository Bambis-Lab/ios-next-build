# AUD-01…AUD-05 — Quellcodeaudit iOS Next 1.6.4

**Scope:** Ausschließlich isolierter Branch `feature/iosnext-164-slider-p0-build27`. Keine Produktionsänderung, kein Merge, kein SideStore-Release. Audit-Baseline wird pro CI-Lauf über Commit und Git-Blob-SHA fixiert.

## AUD-01: Quellcodeinventur
- Inventur aller `.swift`-Dateien im ausgecheckten Commit, einschließlich `Sources/`, `Tests/`, `UITests/`, WireGuard und Swift-Skripten.
- Artefakt `source-lock.json` enthält relativen Pfad, SHA-256, Git-Blob-ID, Byte- und Zeilenanzahl je Datei.
- `git rev-parse HEAD` ist die einzige Versionsquelle. Bereits bekannte Referenz: 162 Swift-Dateien, davon 130 unter `Sources/`, 28 in Tests/UITests und vier weitere.
- **Grenze:** Die Source-Lock-Inventur beweist Dateiintegrität, nicht Laufzeitverhalten.

## AUD-02: SwiftUI und Touch
| ID | Priorität | Stelle | Reproduzierbares Problem / Prüfauftrag |
|---|---|---|---|
| IOS-SL-001 | P0 | `Sources/Design/IOS27DashboardCards.swift:60-63` | Helligkeits-Slider liest HA-Wert direkt; Schreibaufruf für jeden Drag-Wert |
| IOS-SL-002 | P0 | `Sources/Design/IOS27DashboardCards.swift:137-140` | Medienlautstärke direkt an HA-Zustand gebunden |
| IOS-SL-003 | P0 | `Sources/Design/IOS27DashboardCards.swift:435-438` | Lautstärke gekoppelter Medienzone direkt an HA-Zustand gebunden |
| IOS-SL-004 | P0 | `Sources/Design/IOS27DashboardCards.swift:588-591` | Fire-TV-Lautstärke direkt an HA-Zustand gebunden |
| IOS-SL-005 | P1 | `Sources/Core/SliderValueReconciler.swift:60-66` | Nach zwei Sekunden kann letzter Remote-Wert ohne Service-Erfolg übernommen werden; Fehler-/Timeout-Semantik unvollständig |
| IOS-SL-006 | P1 | `Sources/Design/MediaControlSheet.swift` | Bestehender Fix muss gegen echte UI-Drag-Interaktion und gleichzeitige HA-Events getestet werden |

**Abnahme:** UI-Drag-Test mit gleichzeitigem Remote-Update, maximal ein finaler Servicebefehl pro Drag bei Release-only-Slidern, Offline-/Timeout-Verhalten, Accessibility, iPhone/iPad.

## AUD-03: Swift Concurrency und Task-Lebenszyklen
| ID | Priorität | Stelle | Risiko / Negativtest |
|---|---|---|---|
| IOS-CON-001 | P1 | `Sources/Core/SingleFlightRequestScheduler.swift:12-21` | Verschiedene Refresh-Absichten teilen einen Task ohne Request-Schlüssel; alle Aufrufstellen auf gleiche Identität/Parameter prüfen |
| IOS-CON-002 | P1 | `Sources/Core/EntityCommandPipeline.swift:89-130` | In-flight-Seiteneffekt bei Cancellation unbekannt; alte Completion nach Neuverbindung simulieren |
| IOS-CON-003 | P1 | `Sources/Core/HomeAssistantClient.swift:357-375,425-430` | Timeout-/Abbruch-Rennen mit WebSocket-Antworten und Request-Cleanup prüfen |
| IOS-CON-004 | P1 | `Sources/Core/RunnerControlClient.swift:387-431` | Reconnect-Backoff, Resync und Task-Cancellation bei schnellen Netzwechseln testen |
| IOS-CON-005 | P2 | `Sources/Core/LatestValueCommandQueue.swift:21-53` | In-flight-Auftrag und `cancelPending()`: tatsächlicher Geräte-Seiteneffekt kann nach Abbruch noch eintreffen |
| IOS-CON-006 | P2 | `Sources/Core/ChatModel.swift:490-510` | Empfangs-Backoff und Cancellation unter Relay-Wechsel testen |

## AUD-04: Performance und Speicher
| ID | Priorität | Stelle | Messhypothese |
|---|---|---|---|
| IOS-PERF-001 | P1 | `Sources/Features/MediaView.swift:92` | Globales `searchRevision` triggert Medien-Snapshot auch nach Nicht-Medien-Updates |
| IOS-PERF-002 | P1 | `Sources/Features/GlobalSearchView.swift:110-137` | Suchindex-Rebuild auf Main Actor kann bei vielen Entitäten Frames blockieren |
| IOS-PERF-003 | P1 | `Sources/Core/ChatModel.swift:514-538` | Wiederholtes Filtern und Chunk-Summieren pro Envelope skaliert mit Nachrichten-/Chunk-Anzahl |
| IOS-PERF-004 | P2 | `Sources/Features/ChatView.swift:212-218` | Animiertes Auto-Scroll bei Nachrichtenserien/aktiver Benutzer-Scrollposition prüfen |
| IOS-PERF-005 | P2 | `Sources/Features/Owner/Factory/FactoryWorkspaceCoordinator.swift:41-90` | Sequenzielle Remote-Abrufe; Parallelisierung nur bei nachgewiesener Unabhängigkeit |
| IOS-PERF-006 | P2 | `Sources/Features/Owner/Factory/FactoryStandaloneView.swift` | Runner-Modellinitialisierung beim ersten Factory-Render messen |

**Abnahme:** Signposts und Instruments auf iPhone/iPad, p50/p95 von Tabwechseln, Frame-Hitches, Main-Actor-Blockade, CPU, Speicher und Netzwerkbefehlsanzahl. Keine FPS-/Latenzgewinne behaupten, bevor echte Messwerte vorliegen.

## AUD-05: Fehlerregister und Triage
- `Scripts/Audit/source_audit.py` erzeugt im CI `source-lock.json`, `risk-signals.json` und `audit-report.md`. Die Treffer sind **Heuristiken**, nicht automatisch bestätigte Bugs.
- Dieses Register enthält konkrete, im Code nachvollziehbare Stellen und benennt separat Risiken/Hypothesen.
- Jeder Fix braucht Regressionstest, Vorher-/Nachher-Messung und Verweis auf die betroffene Originaldatei.
- Weitere Quellen, einschließlich aller 130 Produktionsdateien, werden durch die automatische Inventur abgedeckt; eine manuelle semantische Zeilenprüfung sämtlicher Dateien ist damit **noch nicht** erledigt.

## Release- und Scope-Gate
- Audit schreibt ausschließlich in den Feature-Branch und erzeugt CI-Artefakte.
- Keine Änderungen an Factory, Home Assistant, `main`, SideStore-Feed oder laufender Infrastruktur.
- SL-01…SL-05-Xcode-Abnahme bleibt unabhängig; Audit-PASS bedeutet nicht iPhone-/iPad-Funktionsabnahme.
