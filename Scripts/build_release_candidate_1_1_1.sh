#!/usr/bin/env bash
set -euo pipefail

EXPECTED_BUNDLE_ID="de.nicofroeba16.iosnext"
EXPECTED_VERSION="1.1.1"
EXPECTED_BUILD="14"
OUT_DIR="${OUT_DIR:-$PWD/ReleaseCandidate-1.1.1}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$OUT_DIR/DerivedData}"

mkdir -p "$OUT_DIR"

XCODE_VERSION="$(xcodebuild -version)"
printf '%s\n' "$XCODE_VERSION"
case "$XCODE_VERSION" in
  *"Xcode 27"*) ;;
  *) echo "Expected Xcode 27" >&2; exit 2 ;;
esac

test "$(xcrun --sdk iphoneos --show-sdk-version)" = "27.0"
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is required" >&2; exit 2; }

# Prepare the same app-only free-sideload target used by the published 1.1.0 build.
# Intentionally no motion capture or motion acceptance command is invoked here.
bash Scripts/prepare_wireguard_dependency.sh
bash Scripts/prepare_free_sideload_project.sh

test -f .free-sideload-ready
grep -q 'IOSNEXT_FREE_SIDELOAD' project.free.yml
! grep -q '      - target: IOSNextPacketTunnel' project.free.yml

rm -rf "$DERIVED_DATA_PATH" "$OUT_DIR/ipa-root" "$OUT_DIR/IOSNext-Free-unsigned.ipa"

xcodebuild build \
  -project IOSNext.xcodeproj \
  -scheme IOSNext \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  MARKETING_VERSION="$EXPECTED_VERSION" \
  CURRENT_PROJECT_VERSION="$EXPECTED_BUILD"

APP="$DERIVED_DATA_PATH/Build/Products/Release-iphoneos/IOSNext.app"
test -d "$APP"
test -f "$APP/Info.plist"
EXEC_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Info.plist")"
test -x "$APP/$EXEC_NAME"
test "$(plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist")" = "$EXPECTED_BUNDLE_ID"
test "$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Info.plist")" = "$EXPECTED_VERSION"
test "$(plutil -extract CFBundleVersion raw -o - "$APP/Info.plist")" = "$EXPECTED_BUILD"
test "$(lipo -archs "$APP/$EXEC_NAME")" = "arm64"
test ! -e "$APP/PlugIns/IOSNextPacketTunnel.appex"

mkdir -p "$OUT_DIR/ipa-root/Payload"
ditto "$APP" "$OUT_DIR/ipa-root/Payload/IOSNext.app"
(
  cd "$OUT_DIR/ipa-root"
  zip -qry "$OUT_DIR/IOSNext-Free-unsigned.ipa" Payload
)
unzip -t "$OUT_DIR/IOSNext-Free-unsigned.ipa"
shasum -a 256 "$OUT_DIR/IOSNext-Free-unsigned.ipa" | tee "$OUT_DIR/IOSNext-Free-unsigned.sha256"
stat -f '%z' "$OUT_DIR/IOSNext-Free-unsigned.ipa" | tee "$OUT_DIR/IOSNext-Free-unsigned.size"

cat > "$OUT_DIR/BUILD_OK.txt" <<EOF
IOSNEXT_RELEASE_CANDIDATE=PASS
VERSION=$EXPECTED_VERSION
BUILD=$EXPECTED_BUILD
BUNDLE_ID=$EXPECTED_BUNDLE_ID
ARCH=arm64
MOTION_CAPTURE=NO
ROLLBACK_VERSION=1.1.0
ROLLBACK_BUILD=13
EOF

cat "$OUT_DIR/BUILD_OK.txt"
