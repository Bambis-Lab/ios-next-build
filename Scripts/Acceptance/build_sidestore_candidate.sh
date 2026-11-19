#!/usr/bin/env bash
# Private, explicit build preparation only. Never publish or sign automatically.
set -euo pipefail
umask 077

fail() { printf '%s\n' "$1" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail 'Authorized macOS/Xcode execution required.'
[[ "${GITHUB_REPOSITORY:-}" != Bambis-Lab/ios-next-build ]] || fail 'Do not build a configured IPA in the public mirror CI.'
: "${CM_COMMIT:?Expected reviewed source commit required}"
: "${EXPECTED_BUILD:?Verified free build number required}"
: "${IOSNEXT_APPROVED_BROKER_URL:?Approved deployment endpoint required}"
: "${1:?New private absolute output directory required}"
export EXPECTED_VERSION=1.8.0
export CM_COMMIT EXPECTED_BUILD IOSNEXT_APPROVED_BROKER_URL
OUT="$1"
[[ "$OUT" == /* && ! -e "$OUT" && ! -L "$OUT" ]] || fail 'Output must be a new absolute path.'
[[ "$CM_COMMIT" =~ ^[0-9a-f]{40}$ && "$EXPECTED_BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'Invalid commit or build number.'
[[ "$(git rev-parse HEAD)" == "$CM_COMMIT" ]] || fail 'Checkout does not match reviewed source.'
[[ -z "$(git status --porcelain)" ]] || fail 'Checkout must be clean.'
command -v xcodegen >/dev/null || fail 'XcodeGen required; no automatic dependency installation.'
case "$(xcodebuild -version | head -n 1)" in
    'Xcode 27'|'Xcode 27.0'|'Xcode 27.0.0') ;;
    *) fail 'Stable Xcode 27.0 required.' ;;
esac
[[ "$(xcrun --sdk iphoneos --show-sdk-version)" == 27.* ]] || fail 'iPhoneOS 27 SDK required.'
python3 - <<'PY'
import os, sys
from pathlib import Path
sys.path.insert(0, 'Scripts/Acceptance')
from verify_release_ipa import valid_broker
p = Path('project.yml').read_text()
v, b = os.environ['EXPECTED_VERSION'], os.environ['EXPECTED_BUILD']
if p.count(f'        MARKETING_VERSION: {v}\n        CURRENT_PROJECT_VERSION: {b}\n') != 1:
    raise SystemExit('Reviewed release version/build not configured in project.yml')
if not valid_broker(os.environ['IOSNEXT_APPROVED_BROKER_URL']):
    raise SystemExit('Invalid approved broker URL')
if not Path('Docs/Releases/1.8.0.md').is_file():
    raise SystemExit('Final reviewed release notes required')
PY
if git ls-tree -r "$CM_COMMIT" | grep '^160000 ' >/dev/null; then
    fail 'Submodule source requires explicit review before snapshot build.'
fi
mkdir -m 700 "$OUT"
mkdir "$OUT/source"
git archive "$CM_COMMIT" | tar -xf - -C "$OUT/source"
cd "$OUT/source"
# Existing side-load preparation is retained, not reimplemented.
bash Scripts/prepare_free_sideload_project.sh > "$OUT/prepare.private.log" 2>&1
xcodebuild -project IOSNext.xcodeproj -scheme IOSNext -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$OUT/DerivedData" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
    "IOSNEXT_FAMILY_BROKER_URL=$IOSNEXT_APPROVED_BROKER_URL" build \
    > "$OUT/build.private.log" 2>&1
APP="$OUT/DerivedData/Build/Products/Release-iphoneos/IOSNext.app"
[[ -x "$APP/IOSNext" ]] || fail 'Missing executable.'
if find "$APP" -type d -name '*.appex' -print | grep . >/dev/null; then
    fail 'Unexpected app extension: review SideStore entitlements before packaging.'
fi
mkdir "$OUT/Payload"
ditto "$APP" "$OUT/Payload/IOSNext.app"
(cd "$OUT" && /usr/bin/zip -qry IOSNext.candidate.ipa Payload)
export OUT
python3 - <<'PY'
import json, os, sys
from pathlib import Path
sys.path.insert(0, 'Scripts/Acceptance')
from verify_device_ipa import verify
root = Path(os.environ['OUT'])
report = verify(root/'IOSNext.candidate.ipa', os.environ['EXPECTED_BUILD'], os.environ['IOSNEXT_APPROVED_BROKER_URL'])
report.update(source_commit=os.environ['CM_COMMIT'], build_flavor='free-sideload',
              signature_verified=False, native_install_verified=False, release_authorized=False)
with (root/'device-structure.json').open('x') as f:
    json.dump(report, f, indent=2)
    f.write('\n')
PY
(cd "$OUT" && shasum -a 256 IOSNext.candidate.ipa > SHA256SUMS.txt)
printf '%s\n' 'Private unsigned candidate only. Native acceptance, signing and publication remain separate.'
