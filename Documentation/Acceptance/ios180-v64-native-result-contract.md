# V6.4 native media evidence contract
The independent runner preflight and local 30/120/300 second WSS media
controls are not substitutes for native distributed execution. This revision
adds native media result fields and a fail-closed offline pair validator.
Each actual run requires an explicitly authorized shared relay, separate role
files, normal verified TLS, one immutable build per duration, and original
XCTest result bundles. Extract the native marker plus actual XCResult device
and host boot-session identity; never fabricate or substitute the fields.
The verifier checks source/run/attempt, product hash, host independence,
relay session, actual named distributed test, exact frame and renewal counts,
monotonic duration and cross-client wall-clock overlap. Wall time requires
separate clock synchronization evidence; it is not a cryptographic proof of
overlap. Successful validation is only that particular media stage, not G03.
Native marker compilation, role-file handoff into disposable simulator and
actual route remain to be verified. No external deployment is performed.
