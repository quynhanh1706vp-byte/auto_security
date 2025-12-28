#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4848c_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true
[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

BK="$OUT/${APP}.bak_before_p4848c_${TS}"
cp -f "$APP" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P4848C_RUNS3_AFTER_REQUEST_ITEMS_ALIAS"
if MARK in s:
    print("[OK] already patched P4848c")
    raise SystemExit(0)

m = re.search(r'^\s*([A-Za-z_]\w*)\s*=\s*Flask\b', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find `<appvar> = Flask` in vsp_demo_app.py")
appvar = m.group(1)

# find the opening "(" of Flask( ... )
pos_flask = m.end()
pos_lpar = s.find("(", pos_flask)
if pos_lpar < 0:
    raise SystemExit("[ERR] cannot find '(' after Flask")

# scan forward to find the matching ')' (ignore quotes/comments basically enough for Flask(...) call)
i = pos_lpar
depth = 0
in_s = False
in_d = False
esc = False

def is_nl(ch): return ch == "\n"

while i < len(s):
    ch = s[i]

    if esc:
        esc = False
        i += 1
        continue

    if in_s:
        if ch == "\\":
            esc = True
        elif ch == "'":
            in_s = False
        i += 1
        continue

    if in_d:
        if ch == "\\":
            esc = True
        elif ch == '"':
            in_d = False
        i += 1
        continue

    # not in quotes
    if ch == "#":
        # skip comment to endline
        j = s.find("\n", i)
        if j < 0:
            i = len(s)
        else:
            i = j + 1
        continue

    if ch == "'":
        in_s = True
        i += 1
        continue
    if ch == '"':
        in_d = True
        i += 1
        continue

    if ch == "(":
        depth += 1
    elif ch == ")":
        depth -= 1
        if depth == 0:
            end_paren = i
            break
    i += 1
else:
    raise SystemExit("[ERR] cannot find matching ')' for Flask(...) call")

# insert after the line that contains the closing ')'
nl = s.find("\n", end_paren)
insert_at = (nl + 1) if nl >= 0 else (end_paren + 1)

block = r"""

# VSP_P4848C_RUNS3_AFTER_REQUEST_ITEMS_ALIAS
def _vsp_p4848c_runs3_contract_payload(obj):
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
def _vsp_p4848c_runs3_after_request(resp):
    try:
        from flask import request
        if request.path.endswith("/api/vsp/runs_v3"):
            ct = resp.headers.get("Content-Type","")
            if "application/json" in ct:
                import json
                raw = resp.get_data(as_text=True) or "{}"
                data = json.loads(raw)
                data = _vsp_p4848c_runs3_contract_payload(data)
                out = json.dumps(data, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Length"] = str(len(resp.get_data() or b""))
                resp.headers["X-VSP-P4848C-RUNS3"] = "1"
    except Exception:
        pass
    return resp
"""
block = block.replace("__APPVAR__", appvar)

s2 = s[:insert_at] + block + s[insert_at:]
p.write_text(s2, encoding="utf-8")
print(f"[P4848c] appvar={appvar} inserted_after=Flask_call_end@{insert_at}")
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
grep -i "X-VSP-P4848C-RUNS3" -n "$OUT/hdr.txt" | tee -a "$OUT/log.txt" || true

python3 - <<'PY' | tee -a "$OUT/log.txt"
import json, pathlib
j = json.loads(pathlib.Path("$OUT/body.json").read_text(encoding="utf-8", errors="replace"))
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__, "runs_type=", type(j.get("runs")).__name__)
print("items_len=", len(j.get("items") or []) if isinstance(j.get("items"), list) else "NA")
print("runs_len=", len(j.get("runs") or []) if isinstance(j.get("runs"), list) else "NA")
print("total=", j.get("total"))
PY
echo "[OK] P4848c done. Close /c/runs tab, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
