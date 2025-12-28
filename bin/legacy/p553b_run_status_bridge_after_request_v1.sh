#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_p553b_${TS}"
echo "[OK] backup => ${APP}.bak_p553b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "P553B_RUN_STATUS_BRIDGE_AFTER_REQUEST_V1" in s:
    print("[OK] already patched")
    raise SystemExit(0)

block = r'''
# =========================
# P553B_RUN_STATUS_BRIDGE_AFTER_REQUEST_V1
# Bridge state/reason into /api/vsp/run_status_v1/<rid> responses that are legacy uireq payloads.
# Keeps existing keys (stage/progress/tail) intact, only adds state/reason/run_dir when missing.
# =========================
@app.after_request
def _p553b_bridge_run_status_v1(resp):
    try:
        # only for path form: /api/vsp/run_status_v1/<...>
        path = getattr(request, "path", "") or ""
        if not path.startswith("/api/vsp/run_status_v1/"):
            return resp
        if resp is None or getattr(resp, "status_code", 0) != 200:
            return resp
        ctype = (resp.content_type or "").lower()
        if "application/json" not in ctype:
            return resp

        raw = resp.get_data()
        if not raw:
            return resp

        j = json.loads(raw.decode("utf-8", errors="replace"))
        if not isinstance(j, dict):
            return resp

        # if already has state, leave it
        if j.get("state") or j.get("status") or j.get("phase"):
            return resp

        # derive rid from payload or path
        rid = (j.get("rid") or j.get("req_id") or j.get("request_id") or j.get("requestId") or "").strip()
        if not rid:
            rid = path.split("/api/vsp/run_status_v1/", 1)[1].strip().split("?",1)[0].strip()
        if not rid:
            return resp

        run_dir = _p552_resolve_run_dir(rid) if "_p552_resolve_run_dir" in globals() else None
        if run_dir and run_dir.is_dir() and "_p553_state_from_artifacts" in globals():
            state, reason = _p553_state_from_artifacts(run_dir)
            j["rid"] = rid
            j["state"] = state
            j["reason"] = reason
            j["run_dir"] = str(run_dir)
        else:
            # fallback: if qs version exists, reuse its logic lightly
            if run_dir and run_dir.is_dir():
                j["rid"] = rid
                j["state"] = "RUNNING"
                j["reason"] = "dir_exists"
                j["run_dir"] = str(run_dir)
            else:
                j["rid"] = rid
                j["state"] = "UNKNOWN"
                j["reason"] = "rid_not_found"

        out = (json.dumps(j, ensure_ascii=False) + "\n").encode("utf-8", errors="replace")
        resp.set_data(out)
        resp.headers["Content-Length"] = str(len(out))
        return resp
    except Exception:
        return resp
'''

# insert before __main__ if present
m=re.search(r"(?m)^if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
if m:
    s2 = s[:m.start()] + block + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + block + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched after_request bridge")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile"

if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
# wait port
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null; then
    echo "[OK] UI up"
    break
  fi
  sleep 1
done

RID="${RID:-VSP_CI_20251219_092640}"
echo "== probe run_status_v1 path (should include state now) =="
curl -sS "$BASE/api/vsp/run_status_v1/$RID" | python3 -m json.tool | sed -n '1,80p'
echo "== probe run_status_v1 qs =="
curl -sS "$BASE/api/vsp/run_status_v1?rid=$RID" | python3 -m json.tool
