#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need awk; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

# locate runs template
TPL=""
if [ -f "templates/vsp_runs_reports_v1.html" ]; then
  TPL="templates/vsp_runs_reports_v1.html"
else
  TPL="$(ls -1 templates 2>/dev/null | egrep -i 'runs|reports' | head -n1 || true)"
  [ -n "$TPL" ] && TPL="templates/$TPL"
fi
[ -n "$TPL" ] && [ -f "$TPL" ] || { echo "[ERR] cannot find runs template under templates/"; exit 2; }

JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS (JS chưa được tạo?)"; exit 2; }

echo "[INFO] template=$TPL"
echo "[INFO] js=$JS"
echo "[INFO] base=$BASE"

cp -f "$TPL" "${TPL}.bak_fix_tpl_${TS}"
echo "[BACKUP] ${TPL}.bak_fix_tpl_${TS}"

# patch template (pass path via ENV to avoid quoting bugs)
export TPL_PATH="$TPL"

python3 - <<'PY'
from pathlib import Path
import os, re

tpl = Path(os.environ["TPL_PATH"])
s = tpl.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUNS_QUICK_ACTIONS_V1"
if marker in s:
    print("[OK] template already patched:", tpl)
else:
    mount_html = '\n<!-- VSP_P1_RUNS_QUICK_ACTIONS_V1 -->\n<div id="vspRunsQuickActionsV1"></div>\n'

    # insert mount after <body> (preferred)
    if "vspRunsQuickActionsV1" not in s:
        s2, n = re.subn(r'(<body\b[^>]*>)', r'\1' + mount_html, s, count=1, flags=re.I)
        if n == 0:
            s2, n = re.subn(r'(</body\s*>)', mount_html + r'\1', s, count=1, flags=re.I)
        s = s2

    # include JS before </body> (safe default filter if asset_v missing)
    js_tag = '\n<script src="/static/js/vsp_runs_quick_actions_v1.js?v={{ asset_v|default(\'\') }}"></script>\n'
    if "vsp_runs_quick_actions_v1.js" not in s:
        s2, n = re.subn(r'(</body\s*>)', js_tag + r'\1', s, count=1, flags=re.I)
        if n == 0:
            s += "\n" + js_tag
        else:
            s = s2

    tpl.write_text(s, encoding="utf-8")
    print("[OK] patched template:", tpl)
PY

# restart best-effort
restart_ok=0
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -qE '^vsp-ui-8910\.service'; then
    echo "[INFO] systemctl restart vsp-ui-8910.service"
    sudo systemctl restart vsp-ui-8910.service || true
    restart_ok=1
  fi
fi

if [ "$restart_ok" -eq 0 ]; then
  if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
    echo "[INFO] restart via bin/p1_ui_8910_single_owner_start_v2.sh"
    rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
    bin/p1_ui_8910_single_owner_start_v2.sh || true
  else
    echo "[WARN] no systemd service and no start script found; restart manually if needed"
  fi
fi

echo "== PROBE 5 tabs =="
curl -fsS -I "$BASE/" | head -n 5
curl -fsS -I "$BASE/vsp5" | head -n 5
curl -fsS -I "$BASE/runs" | head -n 5 || true
curl -fsS -I "$BASE/data_source" | head -n 5
curl -fsS -I "$BASE/settings" | head -n 5
curl -fsS -I "$BASE/rule_overrides" | head -n 5

echo "== PROBE runs page includes JS =="
curl -fsS "$BASE/runs" | grep -n "vsp_runs_quick_actions_v1.js" | head -n 5 || true

echo "== PROBE runs api =="
curl -fsS "$BASE/api/vsp/runs?limit=1" | head -c 220; echo

echo "[DONE] FIX applied. Open Runs & Reports tab, check console: [RunsQuickV1] loaded + running"
