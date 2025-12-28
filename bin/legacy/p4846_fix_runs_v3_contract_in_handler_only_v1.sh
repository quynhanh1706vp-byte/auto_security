#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4846_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

BK="$OUT/${APP}.bak_before_p4846_${TS}"
cp -f "$APP" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

anchor = "/api/vsp/runs_v3"
ai = s.find(anchor)
if ai < 0:
    raise SystemExit("[ERR] cannot find /api/vsp/runs_v3 in vsp_demo_app.py")

# work in a window around the handler
win_start = max(0, ai - 2000)
win_end   = min(len(s), ai + 35000)
w = s[win_start:win_end]

MARK = "VSP_P4846_RUNS_V3_CONTRACT_HANDLER"

# 1) fix any "return jsonify(_vsp_runs_v3_contract(...)" missing closing parens on that line
lines = w.splitlines(True)
paren_fixed = 0
for i, ln in enumerate(lines):
    raw = ln.rstrip("\n")
    if "return jsonify(_vsp_runs_v3_contract(" in raw:
        opens = raw.count("("); closes = raw.count(")")
        if opens > closes:
            raw2 = raw + (")" * (opens - closes))
            lines[i] = raw2 + ("\n" if ln.endswith("\n") else "")
            paren_fixed += 1
w = "".join(lines)

# 2) ensure dict returned by runs_v3 includes items=runs (insert right after runs)
def inject_items_after_runs(txt: str) -> tuple[str,int]:
    n=0
    # double-quote dict
    def repl(m):
        nonlocal n
        if '"items"' in m.group(0) or "'items'" in m.group(0):
            return m.group(0)
        n += 1
        return m.group(1) + '"runs": runs, "items": runs,' + m.group(2)
    txt2 = re.sub(r'(return\s+jsonify\(\s*(?:_vsp_runs_v3_contract\()\s*\{[^{}]{0,5000}?)(\"runs\"\s*:\s*runs\s*,)',
                  repl, txt, count=1, flags=re.S)
    if txt2 != txt:
        return txt2, n

    # single-quote dict
    def repl2(m):
        nonlocal n
        if '"items"' in m.group(0) or "'items'" in m.group(0):
            return m.group(0)
        n += 1
        return m.group(1) + "'runs': runs, 'items': runs," + m.group(2)
    txt3 = re.sub(r"(return\s+jsonify\(\s*(?:_vsp_runs_v3_contract\()\s*\{[^{}]{0,5000}?)(\'runs\'\s*:\s*runs\s*,)",
                  repl2, txt2, count=1, flags=re.S)
    return txt3, n

w2, inj = inject_items_after_runs(w)

# 3) if still not injected (maybe return jsonify(payload)), inject a small normalization right before return jsonify(...)
if inj == 0:
    m = re.search(r'^\s*return\s+jsonify\s*\(', w2, flags=re.M)
    if not m:
        raise SystemExit("[ERR] cannot find return jsonify(...) in runs_v3 window")
    # find indentation
    line_start = w2.rfind("\n", 0, m.start()) + 1
    indent = re.match(r"[ \t]*", w2[line_start:m.start()]).group(0)
    norm = (
        f"{indent}# {MARK}\n"
        f"{indent}try:\n"
        f"{indent}    if isinstance(payload, dict):\n"
        f"{indent}        if 'items' not in payload and 'runs' in payload: payload['items'] = payload.get('runs') or []\n"
        f"{indent}        if 'runs' not in payload and 'items' in payload: payload['runs'] = payload.get('items') or []\n"
        f"{indent}        rr = payload.get('runs') or payload.get('items') or []\n"
        f"{indent}        if payload.get('total') in (None,0) and isinstance(rr, list): payload['total'] = len(rr)\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )
    w2 = w2[:line_start] + norm + w2[line_start:]
    inj = -1

# write back whole file
s2 = s[:win_start] + w2 + s[win_end:]
p.write_text(s2, encoding="utf-8")

print(f"[P4846] paren_fixed={paren_fixed} injected_items={inj}")
print("[OK] wrote vsp_demo_app.py")
PY

# compile gate
python3 -m py_compile "$APP" 2>>"$OUT/log.txt" || { echo "[ERR] py_compile failed; restoring backup" | tee -a "$OUT/log.txt"; cp -f "$BK" "$APP"; exit 3; }
echo "[OK] py_compile ok" | tee -a "$OUT/log.txt"

# restart
if command -v sudo >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

# verify
echo "== [VERIFY] /api/vsp/runs_v3 ==" | tee -a "$OUT/log.txt"
curl -fsS "$BASE/api/vsp/runs_v3?limit=5&include_ci=1" -o "$OUT/body.json"
python3 - <<'PY' <"$OUT/body.json" | tee -a "$OUT/log.txt"
import json,sys
j=json.load(sys.stdin)
print("keys=", sorted(j.keys()))
print("items_type=", type(j.get("items")).__name__)
print("runs_type=", type(j.get("runs")).__name__)
print("items_len=", len(j.get("items") or []) if isinstance(j.get("items"), list) else "NA")
print("runs_len=", len(j.get("runs") or []) if isinstance(j.get("runs"), list) else "NA")
print("total=", j.get("total"))
PY

echo "[OK] P4846 done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
