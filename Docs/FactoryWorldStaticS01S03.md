# Factory World – statische iOS-27-Gesamtansicht S01–S03

## Verbindlicher Produktumfang
- EINE feste orthografische Blender-Gesamtansicht aller 15 Hero Buildings plus realer Gelände-/Straßengeometrie
- iPhone/iPad: Light/Dark ohne Geometrie- oder Kameratransformwechsel
- initial 100% = vollständiges Bild, Pinch-/Button-Zoom 85–250%, begrenzter Pan, Doppeltap/Reset
- keine freien Kamerawinkel, keine animierten Hintergrundobjekte, keine erfundenen Live-Pakete
- Gebäudeoptionen werden als zugängliche native Liste bereitgestellt; visuelle Hotspots erst bei >=160% Zoom
- bestehende Factory-Views zeigen die Welt nur, wenn das geprüfte Paket tatsächlich eingebunden ist; ansonsten ehrlicher Hinweis

## Asset-Lock
Quelle: akzeptierte Blender `HB01_15_District_Polish02.blend`, Original-SHA256
`1c1e131692a3572a44de8c52dc1af3dd25644ef7304ad39636947d742f6123de`.
S01 rendert ALLE sichtbaren Terrain-, Wege- und Gebäudemeshes mit EINER Kamera (nicht nur die 15 Hero Bounding Boxes).
Beide hochkantigen PNGs müssen identische Bildmaße und denselben Kamerablock besitzen; SHA256 und PNG-IHDR werden vor Einbindung validiert.

## Isolierte Ausführung
- Blender-Branch: `Bambis-Lab/factory-ui:feature/factory-world-fw00-fw02`
- iOS-Staging: `Bambis-Lab/ios-next-build:feature/factory-world-static-s01-s03`
- iOS-Source: `FactoryWorldView.swift`, `FactoryWorldStaticAssets.swift`
- Import: `Scripts/stage_factory_world_static.py --commit <full immutable assets commit SHA>`
- Build: Xcode 27, iOS27; Asset-Catalog-Imagesets und lokales JSON im App-Bundle
- Keine main-Merges, Live-Go, source-mesh changes, neuen Factory-Schreibbefehle oder Änderungen an bestehenden HA-/Media-Ansichten

## Acceptance
1. FW-S01: Original-SHA, 15/15 HB, Terrain in Frame, echte Day/Night-PNGs, gemeinsamer Kamerablock, visueller Screenshot-Review.
2. FW-S02: Native iOS-Bildanzeige, korrekter Aspect-Fit, Min/Max-Zoom, Pan-Begrenzung, 100%-Reset, VoiceOver-Liste.
3. FW-S03: Kamera- und Gebäudeanker als verifizierte Daten; spätere Paketpfade ohne Kameradrift möglich.
4. Voller Xcode 27 Build, Simulator-Tests, iPhone-/iPad-Abnahme.
5. Erst danach: optionaler Event-/Paket-Overlay-Block (NICHT Teil von S01–S03).

## Statusgrenzen
Ein grüner Swift-Typecheck alleine beweist weder Bildintegration noch Simulator-Darstellung.
Ein erfolgreicher Xcode-Simulator-Build ohne geprüfte Blender-Assets beweist nur die native Kompilierbarkeit.
Erst vollständig verifizierte Bilder im gebauten App-Bundle und ein Screenshot/UITest bilden die S02-Bild-Abnahme.
