#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_mainrun_${TS}"
echo "[BACKUP] $F.bak_mainrun_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
txt=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_ENSURE_MAIN_RUN_V1" in txt:
    print("[SKIP] already has VSP_ENSURE_MAIN_RUN_V1")
    raise SystemExit(0)

block = r'''
# === VSP_ENSURE_MAIN_RUN_V1 ===
def _vsp_find_flask_app():
  try:
    import flask
  except Exception:
    return None
  for k,v in globals().items():
    try:
      if isinstance(v, flask.Flask):
        return v
    except Exception:
      pass
  return None

if __name__ == "__main__":
  app = _vsp_find_flask_app()
  if app is None:
    raise SystemExit("[FATAL] No Flask app instance found in vsp_demo_app.py")
  # Fixed commercial port 8910
  app.run(host="0.0.0.0", port=8910, debug=False)
# === END VSP_ENSURE_MAIN_RUN_V1 ===
'''.lstrip("\n")

# append at end (safe even if existing __main__ was broken/empty)
txt2 = txt.rstrip() + "\n\n" + block + "\n"
p.write_text(txt2, encoding="utf-8")
print("[OK] appended VSP_ENSURE_MAIN_RUN_V1")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== Health =="
curl -sS -o /dev/null -w "GET / HTTP=%{http_code}\n" http://localhost:8910/ || true
tail -n 50 out_ci/ui_8910.log || true
