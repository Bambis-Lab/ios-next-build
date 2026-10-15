# G99-05 – Real accessibility environment / conditional 1.7.0

Feature branch: fix/iosnext-164-dashboard-sliders-fix01-05
Source baseline: e7229dddc63cc1114b416ac7022ae8f2f961443a

Xcode 27 simctl ui supports content_size and increase_contrast. The test runner must set these states externally.
Reduce Motion and Reduce Transparency use real Settings.app UI automation. The XCTest teardown restores modified simulator switches.
No read-only SwiftUI Environment overrides, private simulator writes, synthetic launch-argument PASS or iPad execution.
Settings UI automation failing is a real acceptance failure, not a reason to skip the gate.

VERSION DECISION: The user authorized naming this candidate 1.7.0 only after full G99 PASS.
Do not merge or SideStore-release. A version metadata change changes SHA and requires final verification on the new 1.7.0 SHA.
