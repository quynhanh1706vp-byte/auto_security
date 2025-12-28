#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need sed; need head

TS="$(date +%Y%m%d_%H%M%S)"

for f in README_COMMERCIAL.md RUNBOOK.md; do
  [ -f "$f" ] && cp -f "$f" "${f}.bak_${TS}" && echo "[BACKUP] ${f}.bak_${TS}"
done

cat > README_COMMERCIAL.md <<'EOF'
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
EOF

cat > RUNBOOK.md <<'EOF'
# RUNBOOK — VSP Commercial UI

## Service
- systemd: vsp-ui-8910.service
- Status:  sudo systemctl status vsp-ui-8910.service --no-pager
- Restart: sudo systemctl restart vsp-ui-8910.service

## Health
- UI health: /api/vsp/ui_health_v2?rid=<RID>

## Logs
- Check service logs:
  journalctl -u vsp-ui-8910.service -n 200 --no-pager

## Common issues (Commercial-grade)
1) KPI shows N/A
- Commercial UI must not display N/A as final state.
- Show 0 / “—” + tooltip (“No data for selected RID”), and ensure API returns full counts.

2) Releases not available
- Check: GET /api/vsp/release_latest includes download_url + audit_url.

3) Console red / assets blocked
- Verify JS asset URL returns 200 with correct JS content-type.
- Browser “allow pasting” warning is NOT an app error.

4) Data Source empty / slow
- Commercial contract should use dedicated paging/filter API.
- Avoid FE calling run_file_allow with internal file paths.
EOF

echo "== README preview =="
sed -n '1,25p' README_COMMERCIAL.md
echo
echo "== RUNBOOK preview =="
sed -n '1,25p' RUNBOOK.md

echo "[OK] wrote README_COMMERCIAL.md and RUNBOOK.md"
