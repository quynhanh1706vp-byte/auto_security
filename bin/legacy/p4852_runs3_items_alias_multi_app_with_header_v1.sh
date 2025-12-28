#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4852_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl; need grep
command -v sudo >/dev/null 2>&1 || true

targets=( "vsp_demo_app.py" "wsgi_vsp_ui_gateway.py" "wsgi_vsp_ui_gateway_v1.py" "wsgi_vsp_ui_gateway_v2.py" )

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re

MARK="VSP_P4852_RUNS3_ITEMS_ALIAS"

def find_flask_assignments(s: str):
    # find: <var> = Flask(
    return [(m.group("var"), m.start(), m.end()-1) for m in re.finditer(r'^(?P<var>[A-Za-z_]\w*)\s*=\s*Flask\s*\(', s, flags=re.M)]

def find_matching_paren_end(s: str, open_paren_pos: int) -> int:
    i = open_paren_pos
    depth = 0
    in_str = None
    triple = False
    esc = False
    while i < len(s):
        ch = s[i]
        nxt3 = s[i:i+3]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            else:
                if triple:
                    if nxt3 == in_str*3:
                        i += 2
                        in_str = None
                        triple = False
                else:
                    if ch == in_str:
                        in_str = None
            i += 1
            continue

        if nxt3 in ("'''",'"""'):
            in_str = nxt3[0]; triple = True; i += 3; continue
        if ch in ("'",'"'):
            in_str = ch; triple = False; i += 1; continue

        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i+1
        i += 1
    raise RuntimeError("cannot find end paren")

def patch_file(path: Path) -> str:
    if not path.exists():
        return f"[SKIP] missing {path}"
    s = path.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        return f"[OK] already patched {path}"

    assigns = find_flask_assignments(s)
    if not assigns:
        return f"[WARN] no `<var> = Flask(` in {path}"

    # inject after each Flask(...) call end (safe, but mark once per file)
    # choose last injection point to reduce line offset complexity
    inserts = []
    for appvar, _st, openp in assigns:
        end = find_matching_paren_end(s, openp)
        inserts.append((end, appvar))

    # build one block per appvar, but keep marker once by including appvar inside block
    blocks = []
    for _end, appvar in inserts:
        blocks.append(f"""

# --- {MARK} ({appvar}) ---
import json as _vsp_p4852_json
from flask import request as _vsp_p4852_req

def _vsp_p4852_runs3_alias(resp):
    try:
        if _vsp_p4852_req.path != "/api/vsp/runs_v3":
            return resp
        resp.headers["X-VSP-P4852-RUNS3"] = "{appvar}"
        ct = resp.headers.get("Content-Type","") or ""
        if "application/json" not in ct:
            return resp
        raw = resp.get_data(as_text=True) or ""
        if not raw.strip():
            return resp
        obj = _vsp_p4852_json.loads(raw)
        if isinstance(obj, dict) and ("runs" in obj) and ("items" not in obj):
            runs = obj.get("runs")
            if isinstance(runs, list):
                obj["items"] = runs
                if "total" not in obj:
                    obj["total"] = len(runs)
                new_raw = _vsp_p4852_json.dumps(obj, ensure_ascii=False)
                resp.set_data(new_raw)
                resp.headers["Content-Length"] = str(len(new_raw.encode("utf-8")))
        return resp
    except Exception:
        return resp

@{appvar}.after_request
def _vsp_p4852_after_request(resp):
    return _vsp_p4852_runs3_alias(resp)
# --- end {MARK} ({appvar}) ---

""")

    # insert blocks at corresponding ends, from back to front to preserve indices
    inserts_sorted = sorted(zip([e for e,_a in inserts],[a for _e,a in inserts]), key=lambda x:x[0], reverse=True)
    s2 = s
    bi = 0
    for end, appvar in inserts_sorted:
        s2 = s2[:end] + blocks[bi] + s2[end:]
        bi += 1

    path.write_text(s2, encoding="utf-8")
    return f"[OK] patched {path} apps={[a for _e,a in inserts]}"

for fn in ["vsp_demo_app.py","wsgi_vsp_ui_gateway.py","wsgi_vsp_ui_gateway_v1.py","wsgi_vsp_ui_gateway_v2.py"]:
    try:
        print(patch_file(Path(fn)))
    except Exception as e:
        print(f"[ERR] patch {fn}: {e}")
PY

# compile only existing files
for f in vsp_demo_app.py wsgi_vsp_ui_gateway.py wsgi_vsp_ui_gateway_v1.py wsgi_vsp_ui_gateway_v2.py; do
  [ -f "$f" ] || continue
  python3 -m py_compile "$f" >/dev/null 2>&1 || { echo "[ERR] py_compile failed on $f" | tee -a "$OUT/log.txt"; exit 2; }
done
echo "[OK] py_compile ok" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then sudo systemctl restart "$SVC"; else systemctl restart "$SVC"; fi
systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "== [VERIFY] header marker + items ==" | tee -a "$OUT/log.txt"
HDR="$OUT/hdr.txt"; BODY="$OUT/body.json"
URL="$BASE/api/vsp/runs_v3?limit=5&include_ci=1"
curl -sS -D "$HDR" -o "$BODY" "$URL"

echo "-- header marker --" | tee -a "$OUT/log.txt"
grep -i "x-vsp-p4852-runs3" -n "$HDR" | tee -a "$OUT/log.txt" || true

python3 - <<PY | tee -a "$OUT/log.txt"
import json, pathlib
p = pathlib.Path("$BODY")
j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__, "items_len=", (len(j["items"]) if isinstance(j.get("items"), list) else "NA"))
print("runs_type=", type(j.get("runs")).__name__, "runs_len=", (len(j["runs"]) if isinstance(j.get("runs"), list) else "NA"))
print("total=", j.get("total"))
PY

echo "[OK] P4852 done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log => $OUT/log.txt"
