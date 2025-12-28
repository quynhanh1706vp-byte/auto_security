#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4850_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$APP" "$OUT/${APP}.bak_before_p4850_${TS}"
echo "[OK] backup => $OUT/${APP}.bak_before_p4850_${TS}" | tee -a "$OUT/log.txt"

MARK="VSP_P4850_RUNS3_ITEMS_ALIAS_AFTER_REQUEST_V1"
if grep -q "$MARK" "$APP"; then
  echo "[OK] $MARK already present; skip append" | tee -a "$OUT/log.txt"
else
  APPVAR="$(python3 - <<'PY'
from pathlib import Path
import re
s=Path("vsp_demo_app.py").read_text(encoding="utf-8", errors="replace")
m=re.search(r'(?m)^([A-Za-z_]\w*)\s*=\s*(?:flask\.)?Flask\s*\(', s)
print(m.group(1) if m else "app")
PY
)"
  echo "[INFO] detected appvar=$APPVAR" | tee -a "$OUT/log.txt"

  cat >> "$APP" <<PY

# === $MARK ===
# Commercial contract: /api/vsp/runs_v3 MUST return both: runs[] and items[] (alias)
def _vsp_p4850_attach_runs3_items_alias(_app):
    try:
        if getattr(_app, "_vsp_p4850_runs3_items_alias_attached", False):
            return
        setattr(_app, "_vsp_p4850_runs3_items_alias_attached", True)
    except Exception:
        pass

    try:
        import json as _json
        from flask import request as _request
    except Exception:
        _json = None
        _request = None

    @_app.after_request
    def _vsp_p4850_runs3_items_alias_after_request(resp):
        try:
            if _json is None or _request is None:
                return resp
            if _request.path != "/api/vsp/runs_v3":
                return resp

            ct = (resp.headers.get("Content-Type") or "").lower()
            if "application/json" not in ct:
                return resp

            raw = resp.get_data(as_text=True) or ""
            raw = raw.strip()
            if not raw:
                return resp

            obj = _json.loads(raw)
            if isinstance(obj, dict):
                if "runs" in obj and "items" not in obj:
                    obj["items"] = obj.get("runs") or []
                if obj.get("total") is None:
                    try:
                        obj["total"] = len(obj.get("items") or obj.get("runs") or [])
                    except Exception:
                        pass

                new_raw = _json.dumps(obj, ensure_ascii=False)
                resp.set_data(new_raw)
                resp.headers["Content-Type"] = "application/json; charset=utf-8"
                resp.headers["X-VSP-P4850-RUNS3-ALIAS"] = "1"
            return resp
        except Exception:
            return resp

    return

try:
    _app = globals().get("${APPVAR}") or globals().get("app") or globals().get("application")
    if _app is not None and hasattr(_app, "after_request"):
        _vsp_p4850_attach_runs3_items_alias(_app)
except Exception:
    pass
# === end $MARK ===
PY

  echo "[OK] appended $MARK into $APP" | tee -a "$OUT/log.txt"
fi

echo "== [CHECK] py_compile ==" | tee -a "$OUT/log.txt"
if ! python3 -m py_compile "$APP" 2>&1 | tee -a "$OUT/log.txt"; then
  echo "[ERR] py_compile failed; restoring backup..." | tee -a "$OUT/log.txt"
  cp -f "$OUT/${APP}.bak_before_p4850_${TS}" "$APP"
  exit 3
fi

echo "== [RESTART] $SVC ==" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" | tee -a "$OUT/log.txt" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "== [VERIFY] /api/vsp/runs_v3 has items ==" | tee -a "$OUT/log.txt"
curl -fsS "$BASE/api/vsp/runs_v3?limit=5&include_ci=1" \
| python3 - <<'PY' 2>/dev/null | tee -a "$OUT/log.txt"
import sys,json
j=json.load(sys.stdin)
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__, "runs_type=", type(j.get("runs")).__name__)
print("items_len=", len(j.get("items") or []) if isinstance(j.get("items"),list) else "NA")
print("runs_len=", len(j.get("runs") or []) if isinstance(j.get("runs"),list) else "NA")
print("total=", j.get("total"))
PY

echo "[OK] P4850 done. Close /c/runs tab, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log => $OUT/log.txt"
