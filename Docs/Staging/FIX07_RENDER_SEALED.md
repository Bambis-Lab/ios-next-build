# FIX-07 — Render staging transport mirror (sealed)

**Status: SOURCE ONLY — RENDER SERVICE NOT CREATED.**

This public-branch mirror contains the intentionally inert `Backend/staging_gateway.py` from the private canonical backend. It does **not** expose secrets or import the real Owner/Family backend. It is not an HA Staging broker.

## Planned Render configuration

- Workspace: **My Workspace** (`tea-db2036ks728c73aj1cng`)
- Region: Frankfurt; service type: Python Web Service; requested plan: **free**
- Branch: `staging/fix07-render-sealed-20261023`
- Automatic deployment: **disabled**
- Build: `python3 -m py_compile Backend/staging_gateway.py`
- Start: `python3 -m Backend.staging_gateway`
- Required settings: `IOSNEXT_STAGE_SEALED=true`, `IOSNEXT_STAGE_DEPLOYMENT=render-synthetic-sealed`
- Hard-disabled: `IOSNEXT_FAMILY_BOOTSTRAP_ENABLED=false`, `IOSNEXT_OWNER_CONTROL_ENABLED=false`, `IOSNEXT_SUPERVISOR_MUTATIONS=false`

The only successful endpoints in the sealed design are `/`, `/healthz`, `/__stage__/status`, which respond with `mode=sealed`, `ha_connected=false`, `owner_enabled=false`, `real_e2e=false`. All HA, chat, Owner and device routes are unavailable. No database, HA credentials, HA network target, Factory/Runner route or production secret is configured.

## Live deployment attempt: refused by Render

- 2026-10-23: Attempt 1, private canonical repository `Bambis-Lab/ios-next` — rejected as invalid/unfetchable source by Render (HTTP 400). No service created.
- 2026-10-23: Attempt 2, public `Bambis-Lab/ios-next-build` on this isolated branch, free plan, auto-deploy disabled — rejected by Render **HTTP 402: Payment information is required**. No service created.
- Subsequent read-only service listing provided no deployed service (null response).
- No billing method, subscription, production write, HA token, staging user, live release flag or SideStore IPA was changed.

**Next external prerequisite:** The Render workspace owner would have to handle billing requirements in Render. This source branch remains inert. Further deployment should be reconsidered only after payment/billing requirements are understood and another explicit go is provided. A sealed health endpoint is never a real HA test and cannot release iOS 1.7.1.
