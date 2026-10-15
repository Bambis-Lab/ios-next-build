# G99-01 – Evidence Lock und Diagnose-Härtung (2026-10-15)

## Baseline (unverändert)

- Repository: `Bambis-Lab/ios-next-build`
- Feature-Branch: `fix/iosnext-164-dashboard-sliders-fix01-05`
- Historischer HEAD vor G99-01: `45a548bfa4f025ad489ec0a6a51e60affd072a4f`
- Fehlgeschlagener Lauf: https://github.com/Bambis-Lab/ios-next-build/actions/runs/38677563190
- Historisches Artefakt: `11946936305` (`IPH-Block-B-iPhone-Targeted-Evidence`, GitHub-Aufbewahrung: 14 Tage)
- ZIP `g99-01-source-evidence-38677563190.zip` wurde separat aus GitHub heruntergeladen; enthält `Targeted.log` und `Targeted.xcresult`.
- Kompilierung und Baseline-Test erfolgreich: https://github.com/Bambis-Lab/ios-next-build/actions/runs/38677563229.
- Targeted UI: **0/3 bestanden**; keinesfalls G99-PASS.

## Nachgewiesene Fehler

1. `testLightSliderInteraction`: Xcode-App-Launch-Timeout vor allen Slider-Assertions. Kein Nachweis eines fachlichen Slider-Defekts aus diesem Versuch.
2. `testLiveOperationsSafeEntryState`: Ziel von y=716.67 auf y=422.67 gescrollt, `enabled=true`, aber `isHittable=false`. Hierarchie- und Overlay-Ursache offen.
3. `testNativeTabNavigationAndMediaDetail`: Nach Media-Tab-Versuch fehlten Media-Summary und Navigationstitel. Ob Tab-Selection, Accessibility oder Fixture verantwortlich ist, noch offen.

## Änderungen dieses Blocks

- XCTest setzt vor Tests ausdrücklich Portrait, protokolliert Launch-Argumente/-Status, schreibt bei Fehlern strukturierte Ziel-, Fenster-, Simulator- und Scrollinformationen mit Screenshot und vollständigem Accessibility-Baum in die `.xcresult`-Attachments.
- Workflow verweigert falschen Branch/SHA, persistiert Toolchain-/Simulator-Daten einschließlich `simctl help ui`, bewahrt `xcodebuild`-Exit-Code, exportiert XCT-Attachments und erfasst bei Fehlern Simulator-Screenshot und aktuelle anwendungsbezogene Systemlogs.
- Keine Produktänderung, kein automatischer Full-G99, keine iPad-Ausführung, kein Merge, kein Release.
- Die frühere `.xcresult` enthält originale XCTest-Attachments. Deren Interpretation bleibt offen, bis sie mit `xcresulttool` auf einem Xcode-Runner exportiert ist.

## Nächstes Gate

Vor G99-02 die wirkliche XCUI-Semantik der Live-Operations-Navigation aus den archivierten Anhängen belegen und danach eine gezielte Änderung mit Einzeltest durchführen.
