#!/usr/bin/env python3
"""Package xcresulttool PNG evidence into a browseable gallery.

No credentials, secrets, untrusted logs or live backend payloads are included.
"""
from __future__ import annotations

import html
import json
from pathlib import Path

root = Path("build/screenshots")
groups = []
all_files = []
for appearance in ("light", "dark"):
    directory = root / appearance
    files = sorted(p for p in directory.rglob("*")
                   if p.is_file() and p.suffix.lower() in (".png", ".jpg", ".jpeg", ".heic"))
    groups.append((appearance, files))
    all_files.extend(files)
    print(f"SCREENSHOTS_{appearance.upper()}={len(files)}")
    if len(files) < 20:
        raise SystemExit(f"SCREENSHOT_EVIDENCE_INCOMPLETE appearance={appearance} count={len(files)}")
if len(all_files) < 40:
    raise SystemExit("SCREENSHOT_EVIDENCE_INCOMPLETE total less than 40")

sections = []
manifest = {
    "version": "1.6.2",
    "build": 25,
    "device": "iPhone 18 Pro Max · iOS 27.0 Simulator",
    "source": "Bambis-Lab/ios-next-build",
    "purpose": "UI evidence only; not a live factory login",
    "images": []
}
for appearance, images in groups:
    thumbs = []
    for image in images:
        rel = image.relative_to(root).as_posix()
        label = image.stem
        manifest["images"].append({"appearance": appearance, "path": rel})
        thumbs.append(
            f'<figure><a href="{html.escape(rel, quote=True)}">'
            f'<img src="{html.escape(rel, quote=True)}" loading="lazy" '
            f'alt="{html.escape(label, quote=True)}"/></a>'
            f'<figcaption>{html.escape(label)}</figcaption></figure>'
        )
    sections.append(f'<section><h2>{appearance.capitalize()} · {len(images)} Screenshots</h2>'
                    + '<div class="gallery">' + "".join(thumbs) + '</div></section>')

page = """<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>iOS Next 1.6.2 · Screenshot Acceptance</title>
<style>body{font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;background:#111722;color:#f2f4f9;margin:0;padding:24px}
main{max-width:1440px;margin:auto}p{color:#bbc4d5;line-height:1.6}
.gallery{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:18px}
figure{margin:0;border:1px solid #283443;border-radius:18px;padding:10px;background:#1b2633}
img{width:100%;height:auto;aspect-ratio:9/19;object-fit:contain;background:#0b1019;border-radius:12px}
figcaption{margin:10px 2px;overflow-wrap:anywhere;font-size:12px;color:#cfdae9}
h2{padding-top:25px}a{color:inherit}</style></head><body><main>
<h1>iOS Next 1.6.2 – UI-Verbesserungen</h1>
<p>iPhone 18 Pro Max · iOS 27.0 · Light + Dark. Erststart,
Chat Relay, Control Center, Runner, Factory Command Deck, OAuth sowie
Home-/Raum-/Medienhintergründe. Dies sind Simulator-Aufnahmen mit
nicht verbundenen oder deterministischen Ansichten: kein Nachweis
einer Live-Anmeldung an der Factory.</p>
""" + "\n".join(sections) + "</main></body></html>"
(root / "index.html").write_text(page, encoding="utf-8")
(root / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
print(f"SCREENSHOT_GALLERY=PASS count={len(all_files)}")
