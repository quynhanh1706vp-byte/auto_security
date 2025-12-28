#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4845_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

BK="$OUT/${APP}.bak_before_p4845_${TS}"
cp -f "$APP" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) remove old middleware blocks (P4843/P4844) if present
for mark in ["VSP_P4843_RUNS_V3_CONTRACT_MW", "VSP_P4844_RUNS_V3_CONTRACT_MW"]:
    s = re.sub(rf"# === {mark} ===.*?# === /{mark} ===\n", "", s, flags=re.S)

# 2) find app creation line robustly
m = re.search(r'^\s*app\s*=\s*Flask\s*\(.*\)\s*$', s, flags=re.M)
if not m:
    # fallback: some files use app=Flask(__name__) without spaces
    m = re.search(r'^\s*app\s*=\s*Flask\s*\(.*\)\s*$', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find `app = Flask(...)` line to attach middleware")

ins = m.end()

MW_MARK="VSP_P4845_RUNS_V3_CONTRACT_MW"
mw = f'''
# === {MW_MARK} ===
try:
    import json as _vsp_json
except Exception:
    _vsp_json = None

try:
    @app.after_request
    def _vsp_p4845_runs_v3_contract(resp):
        try:
            from flask import request as _req
            # accept both /api/vsp/runs_v3 and /api/vsp/runs_v3/
            if not (_req.path == "/api/vsp/runs_v3" or _req.path == "/api/vsp/runs_v3/"):
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

            # normalize keys
            if "items" not in data and "runs" in data:
                data["items"] = data.get("runs") or []
            if "runs" not in data and "items" in data:
                data["runs"] = data.get("items") or []
            rr = data.get("runs") or data.get("items") or []
            if data.get("total") in (None, 0) and isinstance(rr, list):
                data["total"] = len(rr)

            raw = _vsp_json.dumps(data, ensure_ascii=False)
            b = raw.encode("utf-8")
            resp.set_data(b)
            resp.headers["Content-Length"] = str(len(b))
            resp.headers["X-VSP-RUNS3-CONTRACT"] = "P4845"
            return resp
        except Exception:
            return resp
except Exception:
    pass
# === /{MW_MARK} ===
'''.strip("\n") + "\n"

if MW_MARK in s:
    print("[WARN] MW already exists (unexpected after cleanup)")
else:
    s = s[:ins] + "\n\n" + mw + s[ins:]
    print("[OK] injected middleware right after app = Flask(...)")

# 3) Patch runs_v3 handler to include items=runs (for commercial stability)
anchor = "/api/vsp/runs_v3"
ai = s.find(anchor)
if ai < 0:
    print("[WARN] cannot locate runs_v3 anchor for handler patch (MW still works)")
else:
    # patch first dict occurrence with "runs": runs but missing "items"
    window = s[ai: ai+25000]
    if '"items"' not in window:
        # add items next to runs (double-quote)
        window2, n = re.subn(r'("runs"\s*:\s*runs\s*,)',
                             r'\1 "items": runs,', window, count=1)
        if n == 0:
            # single-quote variant
            window2, n = re.subn(r"(\'runs\'\s*:\s*runs\s*,)",
                                 r"\1 'items': runs,", window, count=1)
        if n:
            s = s[:ai] + window2 + s[ai+25000:]
            print("[OK] patched handler dict: items=runs")
        else:
            print("[WARN] handler dict pattern not found; MW will still normalize")
    else:
        print("[OK] handler already has items or window contains items; skip")

# 4) Paren safety: fix any line like return jsonify(_vsp_runs_v3_contract(... ) missing ')'
lines = s.splitlines(True)
fixed = 0
for i, ln in enumerate(lines):
    raw = ln.rstrip("\n")
    if "return jsonify(_vsp_runs_v3_contract(" not in raw:
        continue
    opens = raw.count("("); closes = raw.count(")")
    if opens > closes:
        lines[i] = raw + (")" * (opens - closes)) + ("\n" if ln.endswith("\n") else "")
        fixed += 1
if fixed:
    print(f"[OK] fixed missing parens on {fixed} line(s)")
s = "".join(lines)

p.write_text(s, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py")
PY

# compile gate
python3 -m py_compile "$APP" 2>>"$OUT/log.txt" || { echo "[ERR] py_compile failed (see $OUT/log.txt)"; cp -f "$BK" "$APP"; exit 3; }
echo "[OK] py_compile ok" | tee -a "$OUT/log.txt"

# restart
if command -v sudo >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

# verify contract
echo "== [VERIFY] headers + keys ==" | tee -a "$OUT/log.txt"
curl -sS -D "$OUT/hdr.txt" -o "$OUT/body.json" "$BASE/api/vsp/runs_v3?limit=5&include_ci=1"
grep -i "X-VSP-RUNS3-CONTRACT" -n "$OUT/hdr.txt" | tee -a "$OUT/log.txt" || true
python3 - <<'PY' <"$OUT/body.json" | tee -a "$OUT/log.txt"
import json,sys
j=json.load(sys.stdin)
print("keys=", sorted(j.keys()))
print("items_len=", len(j.get("items") or []) if isinstance(j.get("items"), list) else type(j.get("items")).__name__)
print("runs_len=", len(j.get("runs") or []) if isinstance(j.get("runs"), list) else type(j.get("runs")).__name__)
print("total=", j.get("total"))
PY

echo "[OK] P4845 done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
