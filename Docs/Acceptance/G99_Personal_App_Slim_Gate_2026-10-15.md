# G99 personal-app acceptance – mandatory vs optional (2026-10-15)

**Scope:** iOS Next, iPhone 18 Pro Max, iOS 27, portrait only. Feature branch `fix/iosnext-164-dashboard-sliders-fix01-05`.

**Reason:** G99-05 genuine Settings.app Reduce Motion failed repeatedly even though the
switch could be found and tapped. This proves an unstable automation path, **not**
a product defect. Dynamic Type and Increase Contrast passed on the preceding
targeted run. We do not convert a failed test into a fabricated PASS.

**Mandatory G99:** source/version lock, complete iPhone unit tests, nine product
UI scenarios (including Light/Dark visual acceptance, navigation, media,
chat, sliders, safe entry states, VPN absence), and two real simulator-supported
accessibility settings: Dynamic Type and Increase Contrast. These 11 UI selectors
are in `Scripts/Acceptance/g99_iphone_manifest.txt`.

**Optional, non-blocking:** Reduce Motion and Reduce Transparency genuine
Settings.app switch automation. Their XCTest methods remain in the code and
their selectors in `Scripts/Acceptance/g99_optional_settings_a11y.txt`.
The dedicated `iph-g99-05-accessibility-iphone.yml` workflow is
manual-only. No synthetic accessibility overrides, private simulator writes,
faked success, or suppressed XCTest failures.

**Release decision:** Only a complete PASS of the *revised mandatory G99*
qualifies this personal-app candidate for a conditional 1.7.0 version bump.
Changing version metadata changes the SHA: re-run G99 against that exact new
SHA before treating 1.7.0 as accepted. Do not merge to main, publish an IPA,
SideStore-release, or change the live Factory without separate approval.

**Trigger:** G99 runs on a narrow set of acceptance/version file changes and
supports manual dispatch. This avoids an unrelated source edit triggering a
costly full run.
