#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  echo "canonical-source check failed: $*" >&2
  exit 1
}

# Root XcodeGen spec is the only production project definition.
test -f project.yml || fail "root project.yml is missing"
test -d Sources || fail "root Sources/ is missing"
grep -Eq '^[[:space:]]+- Sources$' project.yml || fail "root project.yml does not compile Sources/"
grep -Eq '^[[:space:]]+- Tests$' project.yml || fail "root project.yml does not compile Tests/"
grep -Eq '^[[:space:]]+- UITests$' project.yml || fail "root project.yml does not compile UITests/"

# No production automation may build or test the historical ZipApp tree.
if grep -RInE \
  'working-directory:[[:space:]]*ZipApp|ZipApp/(project\.yml|IOSNext\.xcodeproj|Sources|Tests|UITests)|cd[[:space:]]+ZipApp' \
  .github/workflows codemagic.yaml Scripts project.yml 2>/dev/null; then
  fail "production automation still references ZipApp"
fi

# Required canonical product features must live in the release tree itself.
test -f Sources/Core/HomeAssistantOAuthService.swift || fail "root OAuth implementation is missing"
test -f Sources/Core/HomeAssistantRegistry.swift || fail "root HA registry model is missing"
test -f Sources/Design/LightControlSheet.swift || fail "root light controls are missing"
test -f Sources/Design/MediaControlSheet.swift || fail "root media controls are missing"
test -f Sources/Resources/live_ha_fixture.json || fail "root Live-HA fixture is missing"
grep -q 'ASWebAuthenticationPresentationContextProviding' Sources/Core/HomeAssistantOAuthService.swift \
  || fail "root OAuth presentation context fix is missing"
grep -q 'callback: \.customScheme' Sources/Core/HomeAssistantOAuthService.swift \
  || fail "root OAuth custom-scheme session is missing"
grep -q 'case stateMismatch' Sources/Core/HomeAssistantOAuthService.swift \
  || fail "root OAuth state validation is missing"
grep -q 'func ios27HoldAction' Sources/Design/IOS27HomeComponents.swift \
  || fail "root iOS 27 hold interaction is missing"

# ZipApp remains historical evidence until an Xcode parity gate authorizes removal.
# It is explicitly non-production and must never regain an automation reference.
if [[ -d ZipApp ]]; then
  test -f ZipApp/LEGACY_NON_PRODUCTION.md \
    || fail "ZipApp exists without the explicit non-production marker"
fi

echo 'Canonical source validation passed: production automation resolves to root Sources/.'
