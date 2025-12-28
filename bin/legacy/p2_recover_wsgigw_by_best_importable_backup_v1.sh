#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
ERRLOG="out_ci/ui_8910.error.log"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [0] show latest error log tail (if any) =="
[ -f "$ERRLOG" ] && tail -n 80 "$ERRLOG" || echo "[WARN] no $ERRLOG"

echo "== [1] find newest backup that IMPORTS + exposes callable application/app =="
BEST="$(python3 - <<'PY'
import glob, os, importlib.util, traceback, sys

F="wsgi_vsp_ui_gateway.py"
cands = [F] + sorted(glob.glob(F+".bak_*"), key=os.path.getmtime, reverse=True)

def test(path):
    try:
        spec=importlib.util.spec_from_file_location("wsgi_test_mod", path)
        mod=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        app = getattr(mod,"application",None) or getattr(mod,"app",None)
        if app is None:
            return False, "missing application/app"
        if not callable(app):
            return False, "application/app not callable"
        return True, "ok"
    except Exception as e:
        return False, repr(e)

for p in cands:
    ok,msg = test(p)
    if ok:
        print(p)
        sys.exit(0)

print("")
sys.exit(3)
PY
)"

if [ -z "${BEST:-}" ]; then
  echo "[ERR] No importable backup found. Need traceback from ERRLOG/import test."
  exit 3
fi
echo "[OK] BEST=$BEST"

echo "== [2] restore BEST into $F (keep current as .bad) =="
cp -f "$F" "${F}.bad_${TS}"
cp -f "$BEST" "$F"
echo "[OK] saved old as ${F}.bad_${TS}"

echo "== [3] py_compile sanity =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== [4] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl daemon-reload || true
  sudo systemctl restart "$SVC" || true
  sleep 0.5
  sudo systemctl status "$SVC" -l --no-pager || true
fi

echo "== [5] quick probe (if up) =="
for u in /runs /vsp5 /api/vsp/rid_latest /api/ui/settings_v2 /api/ui/rule_overrides_v2; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  echo "$u => $code"
done

echo "[DONE] If still not up: check out_ci/ui_8910.error.log for traceback."
