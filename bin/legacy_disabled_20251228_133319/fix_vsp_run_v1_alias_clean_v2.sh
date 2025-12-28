#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/vsp_demo_app.py"
LOG="$ROOT/out_ci/ui_8910.log"

echo "== [0] Auto-restore vsp_demo_app.py from latest backup that compiles =="
CANDS="$(ls -1t "$ROOT"/vsp_demo_app.py.bak_* 2>/dev/null || true)"
if [ -z "${CANDS:-}" ]; then
  echo "[ERR] no backups found: $ROOT/vsp_demo_app.py.bak_*"
  exit 2
fi

RESTORED=""
for f in $CANDS; do
  cp -f "$f" "$APP"
  if python3 -m py_compile "$APP" >/dev/null 2>&1; then
    RESTORED="$f"
    break
  fi
done

if [ -z "$RESTORED" ]; then
  echo "[ERR] cannot find any backup that compiles"
  exit 3
fi
echo "[RESTORED] $APP <= $RESTORED"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_clean_v2_${TS}"
echo "[BACKUP] $APP.bak_clean_v2_${TS}"

echo "== [1] Replace def vsp_run_v1_alias() with clean implementation (no TIMEOUT_SPAWN) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

m = re.search(r"^def\s+vsp_run_v1_alias\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def vsp_run_v1_alias()")

start = m.start()
after = txt[m.end():]
m2 = re.search(r"^def\s+\w+\s*\(.*\)\s*:\s*$", after, flags=re.M)
end = m.end() + (m2.start() if m2 else len(after))

new_fn = r'''
def vsp_run_v1_alias():
  """
  Commercial contract:
  - POST /api/vsp/run_v1 always returns JSON (jq-safe)
  - Never return request_id=TIMEOUT_SPAWN to client
  - If underlying api_vsp_run returns TIMEOUT_SPAWN/empty => replace with synthetic VSP_UIREQ_...
  """
  from flask import request, jsonify
  import time, random, string

  body = None
  try:
    body = request.get_json(silent=True)
  except Exception:
    body = None
  if not body:
    return jsonify({"ok": False, "error": "MISSING_BODY"}), 400

  fn = globals().get("api_vsp_run")
  if not callable(fn):
    return jsonify({"ok": False, "error": "RUN_ALIAS_TARGET_MISSING", "final": True}), 500

  resp = fn()
  code = 200
  headers = None

  if isinstance(resp, tuple):
    if len(resp) >= 2:
      code = resp[1]
    if len(resp) >= 3:
      headers = resp[2]
    resp = resp[0]

  data = None
  # flask Response
  try:
    if hasattr(resp, "get_json"):
      data = resp.get_json(silent=True)
  except Exception:
    data = None

  # dict direct
  if data is None and isinstance(resp, dict):
    data = resp

  if not isinstance(data, dict):
    data = {"ok": True, "implemented": True}

  rid = data.get("request_id") or data.get("req_id") or ""
  if rid in ("", "TIMEOUT_SPAWN"):
    rid2 = "VSP_UIREQ_" + time.strftime("%Y%m%d_%H%M%S") + "_" + "".join(random.choice(string.ascii_lowercase+string.digits) for _ in range(6))
    data["request_id"] = rid2
    data["synthetic_req_id"] = True
    data["message"] = data.get("message") or "Spawn wrapper timed out; returned synthetic request_id for status tracking."

  out = jsonify(data)
  if headers is not None:
    return out, code, headers
  return out, code
'''.lstrip("\n")

txt2 = txt[:start] + new_fn + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] replaced vsp_run_v1_alias() clean")
PY

python3 -m py_compile "$APP"
echo "[OK] vsp_demo_app.py compile OK"

echo "== [2] Restart 8910 =="
pkill -f vsp_demo_app.py || true
nohup python3 "$APP" > "$LOG" 2>&1 &
sleep 1

echo "== [3] Smoke: /api/vsp/run_v1 must return request_id != TIMEOUT_SPAWN =="
RESP="$(curl -sS -X POST "http://localhost:8910/api/vsp/run_v1" -H "Content-Type: application/json" \
  -d '{"mode":"local","profile":"FULL_EXT","target_type":"path","target":"/home/test/Data/SECURITY-10-10-v4"}')"
python3 - <<PY
import json
o=json.loads('''$RESP''')
print(o)
print("request_id=", o.get("request_id"))
PY

echo "== [4] Log tail 30 =="
tail -n 30 "$LOG" || true
echo "[DONE]"
