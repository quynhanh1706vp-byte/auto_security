#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_qstatic_apialias_${TS}"
echo "[BACKUP] ${APP}.bak_qstatic_apialias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_QSTATIC_AND_APIVSP_REDIRECT_V1F"
if MARK in s:
    print("[SKIP] already installed")
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_QSTATIC_AND_APIVSP_REDIRECT_V1F =====================
# 1) Fix broken script URLs that contain an extra quote -> browser encodes as %22:
#    e.g. /%22/static/js/x.js  => redirect to /static/js/x.js
# 2) Fix legacy JS calling /api/vsp/* (extra /vsp) by redirecting to /api/vsp/*

from flask import redirect, request

@app.get("/%22/static/<path:rest>")
def vsp_qstatic_redirect(rest):
    # keep query string
    qs = request.query_string.decode("utf-8", errors="ignore")
    url = "/static/" + rest
    if qs:
        url = url + "?" + qs
    return redirect(url, code=307)

@app.get("/api/vsp/run_file_allow")
def vsp_apivsp_run_file_allow_redirect():
    qs = request.query_string.decode("utf-8", errors="ignore")
    url = "/api/vsp/run_file_allow"
    if qs:
        url = url + "?" + qs
    return redirect(url, code=307)

@app.get("/api/vsp/run_file")
def vsp_apivsp_run_file_redirect():
    qs = request.query_string.decode("utf-8", errors="ignore")
    url = "/api/vsp/run_file"
    if qs:
        url = url + "?" + qs
    return redirect(url, code=307)

@app.get("/api/vsp/rid_latest_gate_root")
def vsp_apivsp_rid_latest_gate_root_redirect():
    qs = request.query_string.decode("utf-8", errors="ignore")
    url = "/api/vsp/rid_latest_gate_root"
    if qs:
        url = url + "?" + qs
    return redirect(url, code=307)
# ===================== /VSP_P1_QSTATIC_AND_APIVSP_REDIRECT_V1F =====================
""").strip() + "\n"

m = re.search(r'\nif\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s2 = s[:m.start()] + "\n\n" + block + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + block + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] inserted redirect block v1f")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] restarted $SVC"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== [VERIFY] %22/static redirect should be 307 then JS MIME =="
curl -fsS -I "$BASE/%22/static/js/vsp_data_source_lazy_v1.js" | sed -n '1,12p'
curl -fsS -L -I "$BASE/%22/static/js/vsp_data_source_lazy_v1.js" | sed -n '1,12p'

echo "== [VERIFY] /api/vsp/run_file_allow redirect should be 307 then 200 =="
RID_EX="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("rid",""))' || true)"
if [ -n "${RID_EX:-}" ]; then
  curl -fsS -I "$BASE/api/vsp/run_file_allow?rid=$RID_EX&path=run_gate_summary.json" | sed -n '1,12p'
  curl -fsS -L "$BASE/api/vsp/run_file_allow?rid=$RID_EX&path=run_gate_summary.json" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"keys=",list(j.keys())[:6])'
else
  echo "[WARN] cannot auto get rid for verify"
fi
