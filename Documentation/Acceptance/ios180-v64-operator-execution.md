# Operator-only distributed execution entrypoint

This is not an automatically launched network workflow. The test relay route
and provisioner have not been authorized or proven reachable. After approval,
two separate disposable hosted macOS runners each restore the exact same
build archive and boot the requested iPhone. Supply each runner's own fresh
role file privately after boot, before the invocation; never use repository
contents, normal artifacts, cache, or command-line bearer values to transfer it.
The explicit operator marker is an additional invocation guard only and is not
proof of authorization. Each runner executes
`run_distributed_native_role.py A|B DURATION PRIVATE_ROLE_FILE` with the
normal CI identity variables and SIM_ID. The runner installs only into an empty
app slot, exclusively creates the role file, runs the exact distributed test,
then removes only its transient role file. The script retains original XCResult
and logs in a restricted temporary directory, not a general artifact glob.
The build layout, simctl listapps JSON behavior, XCTest app reinstall behavior,
native marker and role handoff must still be confirmed on actual macOS before
this can be considered a proven execution path. The current CI validates only
offline helper functions with synthetic fixtures. Do not expose test output
until checked for credential leakage. No production access or network provisioning.
