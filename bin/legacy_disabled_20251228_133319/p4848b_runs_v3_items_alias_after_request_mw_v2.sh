#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4848b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true
[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

BK="$OUT/${APP}.bak_before_p4848b_${TS}"
cp -f "$APP" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P4848B_RUNS3_AFTER_REQUEST_ITEMS_ALIAS"
if MARK in s:
    print("[OK] already patched P4848b")
    raise SystemExit(0)

m = re.search(r'^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find `<appvar> = Flask(` in vsp_demo_app.py")
appvar = m.group(1)

idx = m.end()
line_end = s.find("\n", idx)
if line_end < 0:
    line_end = idx

block = r"""

# VSP_P4848B_RUNS3_AFTER_REQUEST_ITEMS_ALIAS
def _vsp_p4848b_runs3_contract_payload(obj):
    try:
        if isinstance(obj, dict) and ("runs" in obj) and ("items" not in obj):
            obj["items"] = obj.get("runs") or []
        if isinstance(obj, dict) and isinstance(obj.get("items"), list):
            if "total" in obj:
                try:
                    obj["total"] = int(obj.get("total") or len(obj["items"]))
                except Exception:
                    obj["total"] = len(obj["items"])
        return obj
    except Exception:
        return obj

@__APPVAR__.after_request
def _vsp_p4848b_runs3_after_request(resp):
    try:
        from flask import request
        if request.path.endswith("/api/vsp/runs_v3"):
            ct = resp.headers.get("Content-Type","")
            if "application/json" in ct:
                import json
                raw = resp.get_data(as_text=True) or "{}"
                data = json.loads(raw)
                data = _vsp_p4848b_runs3_contract_payload(data)
                out = json.dumps(data, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Length"] = str(len(resp.get_data() or b""))
                resp.headers["X-VSP-P4848B-RUNS3"] = "1"
    except Exception:
        pass
    return resp
"""
block = block.replace("__APPVAR__", appvar)

s2 = s[:line_end+1] + block + s[line_end+1:]
p.write_text(s2, encoding="utf-8")
print(f"[P4848b] appvar={appvar} injected after_request middleware OK")
PY

if ! python3 -m py_compile "$APP" 2> "$OUT/py_compile.err"; then
  echo "[ERR] py_compile failed; showing error:" | tee -a "$OUT/log.txt"
  sed -n '1,200p' "$OUT/py_compile.err" | tee -a "$OUT/log.txt"
  echo "[ERR] restoring backup..." | tee -a "$OUT/log.txt"
  cp -f "$BK" "$APP"
  exit 3
fi
echo "[OK] py_compile ok" | tee -a "$OUT/log.txt"

if command -v sudo >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "== [VERIFY] /api/vsp/runs_v3 ==" | tee -a "$OUT/log.txt"
curl -sS -D "$OUT/hdr.txt" -o "$OUT/body.json" "$BASE/api/vsp/runs_v3?limit=5&include_ci=1"
grep -i "X-VSP-P4848B-RUNS3" -n "$OUT/hdr.txt" | tee -a "$OUT/log.txt" || true

python3 - <<'PY' <"$OUT/body.json" | tee -a "$OUT/log.txt"
import json,sys
j=json.load(sys.stdin)
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__, "runs_type=", type(j.get("runs")).__name__)
print("items_len=", len(j.get("items") or []) if isinstance(j.get("items"), list) else "NA")
print("runs_len=", len(j.get("runs") or []) if isinstance(j.get("runs"), list) else "NA")
print("total=", j.get("total"))
PY

echo "[OK] P4848b done. Close /c/runs tab, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
