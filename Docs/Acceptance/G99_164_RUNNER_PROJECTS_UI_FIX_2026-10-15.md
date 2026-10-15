# Runner & Projects UI Fix (2026-10-15)

Scope: iOS Next iPhone-only feature branch `fix/iosnext-164-dashboard-sliders-fix01-05`. Owner-provided Runner and Projects screenshots.

- Runner: compact capacity counters, actual jobs when supplied, resource metrics,
  persistent Master Runtime link; technical subsystems, services, backups, audit,
  and actions kept behind an initially collapsed diagnostics disclosure.
- Projects: compact summary, readable project list, missing CI communicated
  once with a clear backend explanation, explicit refresh and Owner error state.
- Scroll bottom clearance enlarged for the floating iOS 27 tab bar.
- Existing backend model, action validation, authentication and repo mapping untouched.
- UI never invents CI results: the Owner v2 endpoint must provide `project.ci`.
  For full CI functionality, backend must expose an authorized GitHub CI snapshot
  with actual workflow, SHA, status and timestamp.
- Changed UI source paths trigger the full revised G99 iPhone acceptance; no merge,
  release, backend deployment or live Factory changes were made.
