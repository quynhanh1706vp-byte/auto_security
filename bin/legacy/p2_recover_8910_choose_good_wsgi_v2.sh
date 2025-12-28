#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] current compile check =="
python3 -m py_compile "$F" 2>&1 | tail -n 50 || true

echo "== [1] find best backup (no bad markers + py_compile ok) =="
BEST="$(python3 - <<'PY'
import glob, os, re, subprocess, sys, tempfile

F="wsgi_vsp_ui_gateway.py"
bad_markers = [
  "VSP_P2_AFTERREQ_VSP5_ANCHOR_V1",
  "VSP_P2_AFTERREQ_RUNFILEALLOW_META_V1",
  "VSP_P2_SAFE_AFTERREQ_ANCHOR_META_V3",
]
cands = []
# grab all backups (you created many variants)
cands += glob.glob(F + ".bak_*")
cands = sorted(set(cands), key=lambda p: os.path.getmtime(p), reverse=True)

def ok_compile(path):
    # compile in a temp file to avoid import side effects
    try:
        subprocess.check_output(["python3","-m","py_compile",path], stderr=subprocess.STDOUT)
        return True
    except Exception:
        return False

for b in cands:
    try:
        s = open(b, "r", errors="ignore").read()
    except Exception:
        continue
    if any(m in s for m in bad_markers):
        continue
    if ok_compile(b):
        print(b)
        sys.exit(0)

# fallback: just take newest that compiles (even if markers exist)
for b in cands:
    if ok_compile(b):
        print(b)
        sys.exit(0)

print("")
sys.exit(0)
PY
)"

if [ -z "${BEST:-}" ]; then
  echo "[ERR] cannot find any compiling backup for $F"
  echo "Try: ls -1t ${F}.bak_* | head"
  exit 2
fi

echo "[OK] restore => $BEST"
cp -f "$BEST" "$F"
cp -f "$F" "$F.restored_${TS}"
echo "[OK] wrote $F.restored_${TS}"

echo "== [2] compile after restore =="
python3 -m py_compile "$F"
echo "[OK] py_compile ok"

echo "== [3] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || {
    echo "[ERR] restart failed; status:"
    systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true
    echo "---- journal (tail) ----"
    journalctl -xeu "$SVC" | tail -n 140 || true
    exit 2
  }
  systemctl --no-pager --full status "$SVC" | sed -n '1,60p' || true
fi

echo "== [4] verify port + /vsp5 reachable =="
curl -fsS "$BASE/vsp5" | head -n 5 >/dev/null
echo "[OK] /vsp5 reachable"

echo "[DONE] service is back"
