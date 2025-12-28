#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need sort; need sed; need grep; need ss
need python3
PYBIN="python3"
[ -x .venv/bin/python ] && PYBIN=".venv/bin/python"

TS="$(date +%Y%m%d_%H%M%S)"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [0] snapshot current wsgi =="
cp -f "$F" "${F}.bak_before_rescue_${TS}"
echo "[BACKUP] ${F}.bak_before_rescue_${TS}"

echo "== [1] pick last GOOD backup by executing file (closest to gunicorn import) =="
GOOD=""
mapfile -t BAKS < <(ls -1t "${F}.bak_"* 2>/dev/null | head -n 80 || true)
if [ "${#BAKS[@]}" -eq 0 ]; then
  echo "[ERR] no backups found: ${F}.bak_*"
  exit 2
fi

for b in "${BAKS[@]}"; do
  # skip "before_rescue" snapshots unless needed
  # (still OK, but prefer real earlier stable)
  if echo "$b" | grep -q "before_rescue"; then
    continue
  fi
  echo "[TRY] $b"
  # quick syntax
  if ! "$PYBIN" -m py_compile "$b" >/dev/null 2>&1; then
    echo "      -> py_compile FAIL"
    continue
  fi
  # execute as module file (catches runtime/import errors)
  if "$PYBIN" - <<PY >/dev/null 2>&1
import runpy, sys
runpy.run_path("$b", run_name="__vsp_import_check__")
PY
  then
    GOOD="$b"
    echo "[OK] selected GOOD=$GOOD"
    break
  else
    echo "      -> run_path(import) FAIL"
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] cannot find any importable backup in first ${#BAKS[@]} candidates."
  echo "      show last 80 lines of journal for root-cause:"
  sudo journalctl -u vsp-ui-8910.service -n 80 --no-pager || true
  exit 3
fi

echo "== [2] restore wsgi to GOOD backup =="
cp -f "$GOOD" "$F"
echo "[RESTORED] $F <= $GOOD"

echo "== [3] restart 8910 service =="
sudo rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
sudo systemctl daemon-reload || true
sudo systemctl restart vsp-ui-8910.service || true

sleep 1.2
echo "== [4] ss :8910 =="
ss -ltnp | egrep '(:8910)' || true

echo "== [5] quick curl (if available) =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS -I "$BASE/vsp5" | sed -n '1,8p' || true
curl -fsS "$BASE/api/vsp/runs?limit=1" | head -c 200; echo || true

echo "== [6] FIX JS invalid token: replace leading '# VSP_' comments -> '//' =="
fix_js(){
  local js="$1"
  [ -f "$js" ] || return 0
  cp -f "$js" "${js}.bak_rescue_${TS}"
  # only lines that start with optional spaces then # then optional spaces then VSP_
  python3 - <<PY
from pathlib import Path
import re
p=Path("$js")
s=p.read_text(encoding="utf-8", errors="replace").splitlines(True)
out=[]
n=0
for line in s:
    if re.match(r'^\s*#\s*VSP_', line):
        out.append(re.sub(r'^\s*#\s*', '// ', line))
        n += 1
    else:
        out.append(line)
p.write_text(''.join(out), encoding="utf-8")
print(f"[OK] {p} fixed_hash_comments={n}")
PY
}

fix_js "static/js/vsp_bundle_commercial_v2.js"
fix_js "static/js/vsp_bundle_commercial_v1.js"

if command -v node >/dev/null 2>&1; then
  echo "== [7] node --check JS (must be OK) =="
  [ -f static/js/vsp_bundle_commercial_v2.js ] && node --check static/js/vsp_bundle_commercial_v2.js || true
  [ -f static/js/vsp_bundle_commercial_v1.js ] && node --check static/js/vsp_bundle_commercial_v1.js || true
fi

echo
echo "== NEXT (browser) =="
echo "1) Open /vsp5"
echo "2) DevTools Console:"
echo "   localStorage.removeItem('vsp_rid_latest_v1'); localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "3) Hard refresh: Ctrl+F5"
echo
echo "If 8910 still not up: run -> sudo journalctl -u vsp-ui-8910.service -n 120 --no-pager"
