#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [1] locate wsgi files =="
ls -la wsgi_vsp_ui_gateway*.py 2>/dev/null || true

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_full_${TS}"
echo "[BACKUP] $F.bak_force_full_${TS}"

echo "== [2] force FULL gateway (no exportpdf-only preempt) =="
cat > "$F" <<'PY'
# coding: utf-8
"""
FORCE FULL VSP UI GATEWAY
- Make gunicorn serve the real Flask app (vsp_demo_app.app)
- Avoid any exportpdf-only/preempt wrappers hijacking /api/vsp/*
"""
from vsp_demo_app import app as application  # gunicorn entrypoint
app = application
PY

python3 -m py_compile "$F"
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"

echo "== [3] restart 8910 (commercial) =="
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh || true

echo "== [4] verify WSGI layer on findings endpoint =="
RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1' | jq -er '.items[0].run_id')"
RN="$(curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq -r '.rid_norm // empty')"
echo "RID=$RID"
echo "RID_NORM=$RN"

echo "-- headers (RID_NORM) --"
curl -sS -D- "http://127.0.0.1:8910/api/vsp/findings_preview_v1/${RN}?limit=3" -o /tmp/fp_rn.json | sed -n '1,25p'
echo "-- body --"
jq '{ok,total,items_n,warning,file}' /tmp/fp_rn.json || head -c 400 /tmp/fp_rn.json; echo
