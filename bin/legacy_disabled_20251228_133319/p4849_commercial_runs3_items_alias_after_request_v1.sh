#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4849_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl; need grep

targets=( "vsp_demo_app.py" "wsgi_vsp_ui_gateway.py" "wsgi_vsp_ui_gateway_v1.py" "wsgi_vsp_ui_gateway_v2.py" )
patched_any=0
patched_list=()

for F in "${targets[@]}"; do
  [ -f "$F" ] || continue
  BK="$OUT/${F}.bak_before_p4849_${TS}"
  cp -f "$F" "$BK"
  echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

  python3 - "$F" "$OUT/log.txt" <<'PY'
import sys, re, json
from pathlib import Path

f = Path(sys.argv[1])
log = Path(sys.argv[2])
s = f.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P4849_RUNS3_ITEMS_ALIAS_MW_V1"
if MARK in s:
    log.write_text(log.read_text() + f"[SKIP] {f}: already has {MARK}\n")
    print(f"[SKIP] {f} already patched")
    sys.exit(0)

# Find top-level: <var> = Flask(
m = re.search(r'(?m)^([A-Za-z_]\w*)\s*=\s*(?:flask\.)?Flask\s*\(', s)
if not m:
    # Not fatal; maybe this file isn't the entrypoint
    log.write_text(log.read_text() + f"[WARN] {f}: cannot find top-level Flask() assignment\n")
    print(f"[WARN] {f}: cannot find top-level Flask() assignment")
    sys.exit(3)

appvar = m.group(1)
start = m.end() - 1  # at '('
paren = 0
in_s = False
in_d = False
esc = False

# scan from the '(' to find matching ')'
for i in range(start, len(s)):
    ch = s[i]
    if esc:
        esc = False
        continue
    if ch == "\\":
        esc = True
        continue
    if in_s:
        if ch == "'":
            in_s = False
        continue
    if in_d:
        if ch == '"':
            in_d = False
        continue
    if ch == "'":
        in_s = True
        continue
    if ch == '"':
        in_d = True
        continue
    if ch == "(":
        paren += 1
        continue
    if ch == ")":
        paren -= 1
        if paren == 0:
            end_pos = i + 1
            break
else:
    raise SystemExit(f"[ERR] {f}: cannot find end of Flask(...) call")

# insert right after the statement line that ends Flask(...)
nl = s.find("\n", end_pos)
insert_at = len(s) if nl < 0 else (nl + 1)

block = f"""
# {MARK}
def _vsp_p4849_runs3_contract_response(_resp):
    \"\"\"Commercial contract: ensure /api/vsp/runs_v3 always returns items=list (alias of runs).\"\"\"
    try:
        from flask import request as _req
        if getattr(_req, "path", "") != "/api/vsp/runs_v3":
            return _resp
    except Exception:
        return _resp

    try:
        if getattr(_resp, "status_code", 0) != 200:
            return _resp
        ctype = (_resp.headers.get("Content-Type","") if hasattr(_resp, "headers") else "")
        if "application/json" not in ctype:
            return _resp

        raw = _resp.get_data(as_text=True) or "{{}}"
        obj = json.loads(raw) if isinstance(raw, str) else {{}}
        if not isinstance(obj, dict):
            return _resp

        runs = obj.get("runs")
        items = obj.get("items")

        if not isinstance(items, list):
            if isinstance(runs, list):
                obj["items"] = runs
            else:
                obj["items"] = []

        # normalize total
        if not isinstance(obj.get("total"), int):
            obj["total"] = len(obj.get("items") or [])

        _resp.set_data(json.dumps(obj, ensure_ascii=False))
        _resp.headers["Content-Length"] = str(len(_resp.get_data()))
        _resp.headers["X-VSP-P4849-RUNS3-ALIAS"] = "1"
        return _resp
    except Exception:
        return _resp

try:
    # attach after_request on the discovered app var
    {appvar}.after_request(_vsp_p4849_runs3_contract_response)
except Exception:
    pass

"""

s2 = s[:insert_at] + block + s[insert_at:]
f.write_text(s2, encoding="utf-8")

log.write_text(log.read_text() + f"[OK] patched {f} appvar={appvar} insert_at={insert_at}\n")
print(f"[OK] patched {f} (appvar={appvar})")
PY

rc=$?
if [ "$rc" -eq 0 ]; then
  patched_any=1
  patched_list+=("$F")
elif [ "$rc" -eq 3 ]; then
  # not fatal
  true
else
  echo "[ERR] patch failed on $F (rc=$rc). Restoring backup." | tee -a "$OUT/log.txt"
  cp -f "$BK" "$F"
  exit 2
fi
done

if [ "$patched_any" -ne 1 ]; then
  echo "[ERR] No file patched. Cannot find Flask entrypoint to attach middleware." | tee -a "$OUT/log.txt"
  echo "[HINT] Check which module gunicorn uses (vsp_demo_app.py vs wsgi_vsp_ui_gateway.py)." | tee -a "$OUT/log.txt"
  exit 2
fi

echo "== [CHECK] py_compile ==" | tee -a "$OUT/log.txt"
python3 -m py_compile "${patched_list[@]}" 2>&1 | tee -a "$OUT/log.txt"

echo "== [RESTART] $SVC ==" | tee -a "$OUT/log.txt"
if command -v systemctl >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl restart "$SVC" | tee -a "$OUT/log.txt" || true
    sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
  else
    echo "[WARN] no sudo; please restart service manually" | tee -a "$OUT/log.txt"
  fi
else
  echo "[WARN] no systemctl; please restart manually" | tee -a "$OUT/log.txt"
fi

echo "== [SMOKE] /api/vsp/runs_v3 contract ==" | tee -a "$OUT/log.txt"
HDR="$OUT/hdr.txt"
BODY="$OUT/body.json"
curl -sS -D "$HDR" -o "$BODY" "$BASE/api/vsp/runs_v3?limit=5&include_ci=1" || true

echo "-- header marker --" | tee -a "$OUT/log.txt"
grep -i "X-VSP-P4849-RUNS3-ALIAS" -n "$HDR" | tee -a "$OUT/log.txt" || true

echo "-- json keys/lens --" | tee -a "$OUT/log.txt"
python3 - <<'PY' | tee -a "$OUT/log.txt"
import json, pathlib
p = pathlib.Path("OUT_BODY_PLACEHOLDER")
j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
print("keys=", sorted(j.keys()))
print("items_is_list=", isinstance(j.get("items"), list), "items_len=", (len(j.get("items")) if isinstance(j.get("items"), list) else None))
print("runs_is_list=", isinstance(j.get("runs"), list), "runs_len=", (len(j.get("runs")) if isinstance(j.get("runs"), list) else None))
print("total=", j.get("total"))
PY
