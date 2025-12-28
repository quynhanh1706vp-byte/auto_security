#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4851_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }
cp -f "$APP" "$OUT/${APP}.bak_before_p4851_${TS}"
echo "[OK] backup => $OUT/${APP}.bak_before_p4851_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P4851_RUNS3_ITEMS_ALIAS"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

m = re.search(r'^(?P<var>[A-Za-z_]\w*)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find `<var> = Flask(` assignment in vsp_demo_app.py")

appvar = m.group("var")
start = m.end() - 1  # position at '('

# scan to find matching ')', skipping strings
i = start
depth = 0
in_str = None
triple = False
esc = False
while i < len(s):
    ch = s[i]
    nxt2 = s[i:i+3]
    if in_str:
        if esc:
            esc = False
        elif ch == "\\":
            esc = True
        else:
            if triple:
                if nxt2 == in_str*3:
                    i += 2
                    in_str = None
                    triple = False
            else:
                if ch == in_str:
                    in_str = None
        i += 1
        continue

    # enter string?
    if nxt2 in ("'''", '"""'):
        in_str = nxt2[0]
        triple = True
        i += 3
        continue
    if ch in ("'", '"'):
        in_str = ch
        triple = False
        i += 1
        continue

    if ch == "(":
        depth += 1
    elif ch == ")":
        depth -= 1
        if depth == 0:
            end = i + 1  # after ')'
            break
    i += 1
else:
    raise SystemExit("[ERR] cannot find end of Flask(...) call")

inject_at = end
block = f"""

# --- {MARK} ---
import json as _vsp_p4851_json
from flask import request as _vsp_p4851_req

def _vsp_p4851_runs3_alias(resp):
    try:
        if _vsp_p4851_req.path != "/api/vsp/runs_v3":
            return resp
        ct = resp.headers.get("Content-Type", "") or ""
        if "application/json" not in ct:
            return resp
        raw = resp.get_data(as_text=True) or ""
        if not raw.strip():
            return resp
        obj = _vsp_p4851_json.loads(raw)
        if isinstance(obj, dict) and ("runs" in obj) and ("items" not in obj):
            runs = obj.get("runs")
            if isinstance(runs, list):
                obj["items"] = runs
                if "total" not in obj:
                    obj["total"] = len(runs)
                new_raw = _vsp_p4851_json.dumps(obj, ensure_ascii=False)
                resp.set_data(new_raw)
                resp.headers["Content-Length"] = str(len(new_raw.encode("utf-8")))
        return resp
    except Exception:
        return resp

@{appvar}.after_request
def _vsp_p4851_after_request(resp):
    return _vsp_p4851_runs3_alias(resp)
# --- end {MARK} ---

"""

s2 = s[:inject_at] + block + s[inject_at:]
p.write_text(s2, encoding="utf-8")
print(f"[OK] injected after_request on appvar={appvar} at char={inject_at}")
PY

python3 -m py_compile "$APP" >/dev/null 2>&1 || { echo "[ERR] py_compile failed, restoring backup" | tee -a "$OUT/log.txt"; cp -f "$OUT/${APP}.bak_before_p4851_${TS}" "$APP"; exit 2; }
echo "[OK] py_compile ok" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
else
  systemctl restart "$SVC"
fi
systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "== [VERIFY] /api/vsp/runs_v3 has items ==" | tee -a "$OUT/log.txt"
HDR="$OUT/hdr.txt"; BODY="$OUT/body.json"
URL="$BASE/api/vsp/runs_v3?limit=5&include_ci=1"
curl -sS -D "$HDR" -o "$BODY" "$URL"

python3 - <<PY | tee -a "$OUT/log.txt"
import json, pathlib
p = pathlib.Path("$BODY")
j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__, "items_len=", (len(j["items"]) if isinstance(j.get("items"), list) else "NA"))
print("runs_type=", type(j.get("runs")).__name__, "runs_len=", (len(j["runs"]) if isinstance(j.get("runs"), list) else "NA"))
print("total=", j.get("total"))
PY

echo "[OK] P4851 done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log => $OUT/log.txt"
