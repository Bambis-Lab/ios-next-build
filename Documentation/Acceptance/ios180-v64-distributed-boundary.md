# V6.4 distributed native acceptance boundary
This workflow builds one immutable XCTest product set and boots a single
iPhone 18 Pro Max / iOS 27 on each of two independent macOS execution
sessions. Matching source, attempt and product checksum plus distinct host
boot identities are mandatory. Its green result is not a call acceptance.
No remote relay has been authorized or verified. The original audio fixture
uses known synthetic keys and bearer strings and must remain exclusively on
loopback; do not expose it to a network. Distributed media needs an isolated
per-run relay, a preapproved private network path, fresh role-specific bearer
credentials and pinned public identity keys, verified TLS, bounded lifetime,
no credential logging or artifact inclusion, and a common peer start barrier.
No provisioning or public exposure is authorized by this workflow.
The 30/120/300-second media gates and all security checks remain open.
