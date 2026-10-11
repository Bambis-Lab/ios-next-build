#!/usr/bin/env python3
"""Package xcresulttool PNG evidence into a browseable gallery.

No credentials, secrets, untrusted logs or live backend payloads are included.
"""
from __future__ import annotations

import hashlib
import html
import json
import re
from pathlib import Path

root = Path("build/screenshots")
expected_labels = {
    "01-independent-services-hub", "02-chat-relay-standalone",
    "03-chat-relay-configuration", "04-chat-security",
    "05-control-center-background-entry", "06-control-center-setup",
    "07-factory-custom-preview", "08-factory-preview-sections",
    "09-runner-standalone-background", "10-runner-configuration",
    "11-factory-command-deck-topology", "12-factory-oauth-connect",
    "13-factory-oauth-security", "14-product-home", "15-product-rooms",
    "16-product-chat", "17-product-media", "18-product-system",
    "19-product-light", "20-product-media-detail", "21-product-owner",
    "22-product-wireguard", "23-factory-no-session-detail",
    "24-control-center-setup-security", "25-factory-keychain-error",
    "26-runner-offline", "27-factory-oauth-rejection",
    "28-wireguard-offline-security",
}
groups = []
all_files = []
for appearance in ("light", "dark"):
    directory = root / appearance
    raw_manifest = directory / "manifest.json"
    if not raw_manifest.is_file():
        raise SystemExit(f"SCREENSHOT_MANIFEST_MISSING appearance={appearance}")
    tests = json.loads(raw_manifest.read_text(encoding="utf-8"))
    found = set()
    for test in tests:
        for attachment in test.get("attachments", []):
            name = attachment.get("suggestedHumanReadableName", "")
            match = re.fullmatch(
                rf"iosnext-162-{appearance}-(\d{{2}}-[a-z0-9-]+)_\d+_[0-9A-Fa-f-]+\.png",
                name,
            )
            if match is None:
                raise SystemExit(f"SCREENSHOT_UNRECOGNIZED_ATTACHMENT appearance={appearance}: {name}")
            if attachment.get("isAssociatedWithFailure"):
                raise SystemExit(f"SCREENSHOT_FAILURE_ATTACHMENT: {name}")
            label = match.group(1)
            if label not in expected_labels or label in found:
                raise SystemExit(f"SCREENSHOT_MISSING_OR_DUPLICATE_LABEL: {label}")
            found.add(label)
            original = directory / attachment["exportedFileName"]
            target = directory / (label + ".png")
            if not original.is_file() or target.exists():
                raise SystemExit(f"SCREENSHOT_FILE_MISSING_OR_COLLISION: {label}")
            original.rename(target)
            attachment["exportedFileName"] = target.name
    raw_manifest.write_text(json.dumps(tests, indent=2, ensure_ascii=False), encoding="utf-8")
    if found != expected_labels:
        raise SystemExit(f"SCREENSHOT_EXPECTED_LABELS_MISMATCH appearance={appearance} missing={sorted(expected_labels-found)}")
    files = sorted(directory.glob("[0-9][0-9]-*.png"))
    groups.append((appearance, files))
    all_files.extend(files)
    print(f"SCREENSHOTS_{appearance.upper()}={len(files)}")
    if len(files) != 28:
        raise SystemExit(f"SCREENSHOT_EVIDENCE_INCOMPLETE appearance={appearance} count={len(files)} expected=28")
if len(all_files) != 56:
    raise SystemExit("SCREENSHOT_EVIDENCE_INCOMPLETE total expected=56")

# An inadvertent duplicate view cannot satisfy the visual gate merely by
# producing 56 image files. Cryptographic equality is a hard failure.
digests = {}
for path in all_files:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest in digests:
        raise SystemExit(
            f"SCREENSHOT_DUPLICATE: {path} equals {digests[digest]}"
        )
    digests[digest] = path
print("SCREENSHOT_DUPLICATE_CHECK=PASS")

sections = []
manifest = {
    "version": "1.6.2",
    "build": 25,
    "device": "iPhone 18 Pro Max · iOS 27.0 Simulator",
    "source": "Bambis-Lab/ios-next-build",
    "purpose": "UI evidence only; simulator states are explicitly simulated; no live backend authentication",
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
