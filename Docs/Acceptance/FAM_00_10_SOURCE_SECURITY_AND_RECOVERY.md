# FAM-00–FAM-10 — iOS Next family onboarding (source-only, unreleased)

## Source lock
- Repository: Bambis-Lab/ios-next-build
- Shipped 1.7.0 SOURCE SHA: 9adf58c205400147f95c89e44cc71564e0c30d2d, per official Bambis-Lab/ios-next-releases/release-manifests/1.7.0.json; IPA SHA-256: 9b8a11ccd652c3a2bb6fcbc32a313a77af7eae509580cf6ac5e4eec8f8def858 (Build 28).
- Earlier G99 change SHA: 25b1176ecd930bff8db04f804d62acf550af83c7. Release 1.7.0 source was 10 commits ahead and changed RunnerControlClient, RunnerDashboardView, OwnerProjectsView, ProductAcceptanceRootView and G99 tests.
- Merge SHA 4daebf4a97a94a49d06b6dbc51824f6f1cff54c1 preserved the published release source as a parent and applied isolated family feature files without reverting the Runner/Project fixes.
- Published 1.7.0 release CI patched original project.yml 1.6.4/27 into 1.7.0/28 during packaging; the source metadata correctly remains 1.6.4/27 until separate release approval.
- The release source comparison is definitive but a new 1.7.1 IPA remains unbuilt and unreleased.
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

## FAM-11 integration outcomes and remaining release gates
- Family mode is opt-in, disabled unless explicit backend configuration enables it.
- Old /v2/auth/bootstrap denies access when family enrollment is enabled; static legacy chat tokens are denied too. Plan the cross-client migration before enabling.
- Family chat grants now use the verified Broker HTTPS origin and integrate with /v1/chat/session, contacts, identities, messages, and tickets. No guessed relay address or token redirects.
- Chat role for a family session is the verified member-only claim, not Owner display name. HA login alone never issues Factory/Runner admin tokens.
- The independent existing Owner token + P-256 device approval stays mandatory even for the Nico profile; a separate backend Owner authorization design and real-device approval remain required.
- Keys for newly registered family chat are separated by stable HA user ID in Keychain, with old chat keys left in the legacy namespace. No claim that old E2EE messages survive deletion.
- Device IDs rotate when the signing private key is missing; revoked or different-key devices cannot reuse an old registration.
- Real stable HA user IDs, the broker URL, and any deployment credentials are never in Git. Live user matching, staged Factory Owner sessions, and real E2E remain open.
- CI synthetic family UI screenshots are not proof of real Home Assistant login. SideStore signing and eventual release require separate explicit Go.
