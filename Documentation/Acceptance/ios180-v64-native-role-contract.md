# Native role-only contract
Distributed XCTest entry points testDistributedA/B never use local deterministic
credentials when a role file is absent or invalid. The test host must receive
one role-only JSON file iosnext-v64-test-role.json in its Application Support
directory by an authorized private provisioning mechanism. Fields are version,
role, callID, baseURL, duration, expiresAt, signingSeed, peerSigningKey,
peerAgreementKey, tokens, grantExpiries. camelCase keys. Credentials are synthetic
test-only and must not be embedded into build products, passed in command-line
arguments, logged, or included in result/artifact bundles. No provisioning
mechanism or externally reachable relay has been authorized or verified. Only
the validation logic is invoked by the preflight; the distributed media tests
remain disabled until that separate gate is satisfied. HTTPS/WSS uses normal
platform certificate trust and same-origin restrictions, never a TLS bypass.
