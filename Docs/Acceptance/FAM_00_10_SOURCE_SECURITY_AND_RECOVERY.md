# FAM-00–FAM-10 — iOS Next family onboarding (source-only, unreleased)

## Source lock
- Repository: Bambis-Lab/ios-next-build
- Base SHA: 25b1176ecd930bff8db04f804d62acf550af83c7
- Earlier G99 passing source: 76562a32ee3a0073b9eb448c2ac489107f71836a
- Source base metadata: MARKETING_VERSION=1.6.4, CURRENT_PROJECT_VERSION=27
- The actual signed SideStore 1.7.0 IPA cannot be byte-matched from these sources. Do NOT claim 1.7.1 release readiness before reconciling the shipped IPA and this branch.
- Branch: feature/iosnext-171-family-bootstrap. Nothing merged, no live changes.

## Architecture, fail-closed
1. HA OAuth authorization and HA websocket auth/current_user.id remain authoritative.
2. A vetted HTTPS family broker endpoint must be embedded by an approved build via IOSNEXT_FAMILY_BROKER_URL build setting (Info.plist key IOSNextFamilyBrokerURL); no guessed DNS host, no token in URL.
3. Client creates independent P-256 device key with WhenUnlockedThisDeviceOnly and ios- UUID.
4. POST v2/family/challenge and POST v2/family/register with the HA bearer and P-256 challenge signature; no redirects permitted.
5. Backend maps stable HA IDs to nico/mika/juli/gabi/timo and validates device proof, never trusting names or a client role.
6. App accepts profile only when server HA ID AND device ID match locally verified values. Nico profile is NOT Owner authorization; Owner requires independent device enrollment.
7. Member profiles hide Factory/Live Operations administration in System; all HA-authorized entities remain available through Rooms and Search.
8. When family bootstrap is unavailable, show a neutral, unverified home state (Rooms) rather than falling back to Nico. HA connection stays usable. Chat bootstrap remains a separate existing service; no existing tokens are replaced until valid.
9. HA tokens and P-256 private keys are never logged or inserted into source, backups, or diagnostics.

## Restore after SideStore reinstall
- Updating an existing IPA may preserve App sandbox but is not guaranteed across signing changes; no automatic deletion of previous application.
- Full deletion destroys local app container (and may destroy encryption material depending on Keychain/signing behavior).
- On fresh HA login, backend reuses the stable family account mapping and re-enrolls a device separately with its own key.
- Old end-to-end encrypted chat messages cannot be restored solely from a HA login: the E2EE private key is not server-recoverable. Display identity/safety-number change on key regeneration.
- Owner devices NEVER inherit privileged sessions automatically after reinstall.
- SideStore Apple-ID errors -80045/-1001 are signing/network issues unrelated to HA login.

## Known blockers before any production acceptance
- Verify actual shipped 1.7.0 binary/source revision.
- Set actual HA user IDs only on the private backend (never Git), plus explicit Owner allowlist.
- Configure and test TLS reachability of actual Family Broker host (never invent/guess a public URL).
- Confirm actual HA account permissions and real device approval rules.
- Run CI and Xcode iPhone simulator, collect actual artifacts; do not claim real HA account validation from synthetic simulator tests.
- Publish IPA/source only after a separate GO for release.

## Required commands
Backend: PYTHONPATH=. python3 -m unittest Backend.tests.test_family_registry -v
Backend mirror: python3 Scripts/sync_owner_addon.py --check
iOS unit on Xcode 27: xcodebuild test -project IOSNext.xcodeproj -scheme IOSNext -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:IOSNextTests/FamilyIdentityTests CODE_SIGNING_ALLOWED=NO

Never print raw HA token, signing key, chat token, Owner token, or authentication headers.
