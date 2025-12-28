# VersaSecure Platform (VSP) — Commercial UI

## Purpose
CIO-level security overview with 5 tabs: Dashboard, Runs & Reports, Data Source, Settings, Rule Overrides.
No dev/debug content exposed in UI.

## Access
- UI Base: http://127.0.0.1:8910
- Dashboard: /vsp5
- Runs & Reports: /runs
- Releases: /releases
- Data Source: /data_source
- Settings: /settings
- Rule Overrides: /rule_overrides

## Release (Golden RID)
- Latest release API: /api/vsp/release_latest
- Download ZIP: /api/vsp/release_download?rid=<RID>
- Audit JSON: /api/vsp/release_audit?rid=<RID>

## Commercial self-check
Run:
  bin/commercial_selfcheck_v1.sh <RID>

Expected:
- All tabs return HTTP 200
- release_latest contains: rid + download_url + audit_url
- /releases shows at least 1 item
- download + audit for RID OK

## Commercial rules (non-negotiable)
- FE must not read filesystem paths or show internal paths in UI.
- Avoid leaking debug strings (e.g., “UNIFIED FROM findings_unified.json”).
- Prefer tab-scoped API contracts (stateless) over legacy / file-proxy patterns.
