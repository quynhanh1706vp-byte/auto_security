#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_runs_reports_v1.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$TPL" "${TPL}.bak_rm_5tabs_${TS}"
echo "[BACKUP] ${TPL}.bak_rm_5tabs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("templates/vsp_runs_reports_v1.html")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# remove any include of 5tabs filler
s = re.sub(r"\n?\s*<script[^>]+src=['\"]/static/js/vsp_fill_real_data_5tabs_p1_v1\.js[^>]*>\s*</script>\s*\n?", "\n", s, flags=re.I)

# (optional harden) remove any bundle includes from /runs standalone page
s = re.sub(r"\n?\s*<script[^>]+src=['\"]/static/js/vsp_bundle_commercial_v[0-9]+\.js[^>]*>\s*</script>\s*\n?", "\n", s, flags=re.I)
s = re.sub(r"\n?\s*<script[^>]+src=['\"]/static/js/vsp_runs_tab_resolved_v1\.js[^>]*>\s*</script>\s*\n?", "\n", s, flags=re.I)
s = re.sub(r"\n?\s*<script[^>]+src=['\"]/static/js/vsp_app_entry_safe_v1\.js[^>]*>\s*</script>\s*\n?", "\n", s, flags=re.I)

if s == orig:
    print("[OK] no changes needed (no 5tabs/bundle includes found).")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] removed 5tabs/bundle includes from /runs template")

PY

echo "== verify: /runs template must NOT include vsp_fill_real_data_5tabs_p1_v1.js =="
grep -n "vsp_fill_real_data_5tabs_p1_v1\.js" -n "$TPL" || echo "[OK] not found"

# restart UI
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "[DONE] Now open Incognito: http://127.0.0.1:8910/runs"
echo "Tip: DevTools > Application > Clear site data (once) if any cached JS still interferes."
