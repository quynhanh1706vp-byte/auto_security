#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4843_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

BK="$OUT/${APP}.bak_before_p4843_${TS}"
cp -f "$APP" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# ---------------------------
# (A) RESCUE SyntaxError: remove ONE trailing ')' if line has more ')' than '(' by 1
# only for lines involving request.args.get(...) (commercial-safe heuristic)
# ---------------------------
lines = s.splitlines(True)
fixed = 0
fixed_examples = []

def try_fix_line(line: str) -> str:
    global fixed
    raw = line.rstrip("\n")
    if "request.args.get" not in raw:
        return line
    # count parens ignoring strings (rough but ok for this pattern)
    opens = raw.count("(")
    closes = raw.count(")")
    if closes - opens != 1:
        return line
    # remove ONE trailing ')' if exists
    m = re.search(r"\)\s*$", raw)
    if not m:
        return line
    new_raw = re.sub(r"\)\s*$", "", raw, count=1)
    if new_raw != raw:
        fixed_examples.append((raw.strip(), new_raw.strip()))
        return new_raw + ("\n" if line.endswith("\n") else "")
    return line

new_lines = []
for ln in lines:
    new_ln = try_fix_line(ln)
    if new_ln != ln:
        fixed += 1
    new_lines.append(new_ln)

s2 = "".join(new_lines)

# extra targeted cleanup: common exact patterns
s2, n1 = re.subn(r'limit\s*=\s*int\s*\(\s*request\.args\.get\(\s*"limit"\s*,\s*"50"\s*\)\s*\)\s*\)\s*',
                 'limit=int(request.args.get("limit","50"))', s2)
s2, n2 = re.subn(r'offset\s*=\s*int\s*\(\s*request\.args\.get\(\s*"offset"\s*,\s*"0"\s*\)\s*\)\s*\)\s*',
                 'offset=int(request.args.get("offset","0"))', s2)
if n1 or n2:
    fixed += (n1+n2)

print(f"[P4843] syntax-rescue: lines_fixed={fixed}")
if fixed_examples:
    print("[P4843] examples (before -> after):")
    for a,b in fixed_examples[:5]:
        print(" -", a, "=>", b)

# ---------------------------
# (B) Add AFTER_REQUEST middleware for /api/vsp/runs_v3 contract
# - always ensure items + runs + total
# - minimal invasive; works regardless of handler implementation
# ---------------------------
MARK = "VSP_P4843_RUNS_V3_CONTRACT_MW"
if MARK in s2:
    print("[P4843] middleware already present; skip inject")
    p.write_text(s2, encoding="utf-8")
    sys.exit(0)

mw = r'''
# === {MARK} ===
# Commercial contractizer for /api/vsp/runs_v3: ensure {ok, runs, items, total}
try:
    import json as _vsp_json
except Exception:
    _vsp_json = None

try:
    @app.after_request
    def _vsp_p4843_runs_v3_contract(resp):
        try:
            # local import to avoid import-order issues
            from flask import request as _req
            if _req.path != "/api/vsp/runs_v3":
                return resp
            if _vsp_json is None:
                return resp
            mt = (getattr(resp, "mimetype", "") or "")
            if "json" not in mt:
                return resp
            data = None
            try:
                data = resp.get_json(silent=True)
            except Exception:
                data = None
            if not isinstance(data, dict):
                return resp

            # normalize
            if "items" not in data and "runs" in data:
                data["items"] = data.get("runs") or []
            if "runs" not in data and "items" in data:
                data["runs"] = data.get("items") or []
            rr = data.get("runs") or data.get("items") or []
            if data.get("total") in (None, 0) and isinstance(rr, list):
                data["total"] = len(rr)

            raw = _vsp_json.dumps(data, ensure_ascii=False)
            resp.set_data(raw.encode("utf-8"))
            resp.headers["Content-Length"] = str(len(raw.encode("utf-8")))
            resp.headers["X-VSP-P4843-RUNS3"] = "1"
            return resp
        except Exception:
            return resp
except Exception:
    pass
# === /{MARK} ===
'''.replace("{MARK}", MARK).strip("\n") + "\n"

# inject right after "app = Flask"
m = re.search(r'^\s*app\s*=\s*Flask\s*\(.*\)\s*$', s2, flags=re.M)
if m:
    ins = m.end()
    s3 = s2[:ins] + "\n\n" + mw + s2[ins:]
    print("[P4843] injected middleware after app=Flask(...)")
else:
    # fallback: inject after imports block (first blank line after imports)
    m2 = re.search(r'^(import .+|from .+ import .+)(\r?\n)+', s2, flags=re.M)
    if m2:
        ins = m2.end()
        s3 = s2[:ins] + "\n" + mw + s2[ins:]
        print("[P4843] injected middleware after imports")
    else:
        s3 = mw + "\n" + s2
        print("[P4843] injected middleware at top (fallback)")

p.write_text(s3, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py")
PY

# compile gate
if ! python3 -m py_compile "$APP" 2>>"$OUT/log.txt"; then
  echo "[ERR] py_compile still failed. Showing context..." | tee -a "$OUT/log.txt"
  python3 - <<'PY' | tee -a "$OUT/log.txt"
import traceback
try:
    import py_compile
    py_compile.compile("vsp_demo_app.py", doraise=True)
except Exception:
    traceback.print_exc()
PY
  echo "[ERR] restoring backup..." | tee -a "$OUT/log.txt"
  cp -f "$BK" "$APP"
  exit 3
fi
echo "[OK] py_compile ok" | tee -a "$OUT/log.txt"

# restart
if command -v sudo >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

# smoke
echo "== [SMOKE] runs_v3 contract ==" | tee -a "$OUT/log.txt"
curl -fsS "$BASE/api/vsp/runs_v3?limit=5&include_ci=1" -D "$OUT/hdr.txt" -o "$OUT/body.json"
python3 - <<'PY' <"$OUT/body.json" | tee -a "$OUT/log.txt"
import json,sys
j=json.load(sys.stdin)
print("keys=", sorted(j.keys()))
print("items_len=", len(j.get("items") or []) if isinstance(j.get("items"), list) else type(j.get("items")).__name__)
print("runs_len=", len(j.get("runs") or []) if isinstance(j.get("runs"), list) else type(j.get("runs")).__name__)
print("total=", j.get("total"))
PY
echo "== headers marker ==" | tee -a "$OUT/log.txt"
grep -i "X-VSP-P4843-RUNS3" -n "$OUT/hdr.txt" | tee -a "$OUT/log.txt" || true

echo "[OK] P4843 done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
