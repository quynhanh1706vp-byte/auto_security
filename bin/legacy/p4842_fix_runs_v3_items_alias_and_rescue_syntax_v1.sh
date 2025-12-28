#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4842_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

BK="$OUT/${APP}.bak_before_p4842_${TS}"
cp -f "$APP" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# --- (A) Rescue common unmatched-paren mistakes introduced by patches ---
patterns = [
    # limit=int(request.args.get("limit","50")))
    (re.compile(r'limit\s*=\s*int\s*\(\s*request\.args\.get\(\s*"limit"\s*,\s*"50"\s*\)\s*\)\s*\)\s*'), 'limit=int(request.args.get("limit","50"))'),
    (re.compile(r"limit\s*=\s*int\s*\(\s*request\.args\.get\(\s*'limit'\s*,\s*'50'\s*\)\s*\)\s*\)\s*"), "limit=int(request.args.get('limit','50'))"),
    # offset=int(request.args.get("offset","0")))
    (re.compile(r'offset\s*=\s*int\s*\(\s*request\.args\.get\(\s*"offset"\s*,\s*"0"\s*\)\s*\)\s*\)\s*'), 'offset=int(request.args.get("offset","0"))'),
    (re.compile(r"offset\s*=\s*int\s*\(\s*request\.args\.get\(\s*'offset'\s*,\s*'0'\s*\)\s*\)\s*\)\s*"), "offset=int(request.args.get('offset','0'))"),
]
fix_count = 0
for rx, rep in patterns:
    s2, n = rx.subn(rep, s)
    if n:
        fix_count += n
        s = s2
print(f"[P4842] paren-rescue fixes applied: {fix_count}")

# --- (B) Contractize /api/vsp/runs_v3: always return items + total (commercial contract) ---
anchor = "/api/vsp/runs_v3"
ai = s.find(anchor)
if ai < 0:
    print("[ERR] cannot find /api/vsp/runs_v3 in vsp_demo_app.py")
    sys.exit(3)

# Find a "return jsonify(" after the anchor
m = re.search(r'^[ \t]*return[ \t]+jsonify\s*\(', s[ai:], flags=re.M)
if not m:
    print("[ERR] cannot find 'return jsonify(' after runs_v3 anchor")
    sys.exit(4)

ret_pos = ai + m.start()
line_start = s.rfind("\n", 0, ret_pos) + 1
indent = re.match(r'[ \t]*', s[line_start:ret_pos]).group(0)

# Find start of arg inside jsonify(...)
jsonify_pos = s.find("jsonify", ret_pos)
open_pos = s.find("(", jsonify_pos)
if open_pos < 0:
    print("[ERR] malformed jsonify call (no '(')")
    sys.exit(5)
arg_start = open_pos + 1

# Match closing paren of jsonify call (simple depth scan)
depth = 1
k = arg_start
end_paren = -1
while k < len(s):
    ch = s[k]
    if ch == "(":
        depth += 1
    elif ch == ")":
        depth -= 1
        if depth == 0:
            end_paren = k
            break
    k += 1
if end_paren < 0:
    print("[ERR] cannot find matching ')' for jsonify(...) in runs_v3 handler")
    sys.exit(6)

arg_expr = s[arg_start:end_paren].strip()

# Replace the whole return-line region (from line_start to end-of-line containing the return)
line_end = s.find("\n", end_paren)
if line_end < 0:
    line_end = len(s)

replacement = (
f"{indent}payload = {arg_expr}\n"
f"{indent}# P4842: COMMERCIAL contract for runs_v3\n"
f"{indent}# - UI may read payload.items (legacy) OR payload.runs (new)\n"
f"{indent}# - ensure total is consistent\n"
f"{indent}if isinstance(payload, dict):\n"
f"{indent}    if 'items' not in payload and 'runs' in payload:\n"
f"{indent}        payload['items'] = payload.get('runs') or []\n"
f"{indent}    if 'runs' not in payload and 'items' in payload:\n"
f"{indent}        payload['runs'] = payload.get('items') or []\n"
f"{indent}    if payload.get('total') in (None, 0):\n"
f"{indent}        rr = payload.get('runs') or payload.get('items') or []\n"
f"{indent}        if isinstance(rr, list):\n"
f"{indent}            payload['total'] = len(rr)\n"
f"{indent}return jsonify(payload)\n"
)

s_new = s[:line_start] + replacement + s[line_end+1:]
if s_new == orig:
    print("[WARN] no changes detected (unexpected).")
else:
    s = s_new
    print("[P4842] patched runs_v3 jsonify => items alias + total normalization")

p.write_text(s, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py")
PY

# Compile gate
if ! python3 -m py_compile "$APP" 2>>"$OUT/log.txt"; then
  echo "[ERR] py_compile failed; restoring backup..." | tee -a "$OUT/log.txt"
  cp -f "$BK" "$APP"
  python3 -m py_compile "$APP" || true
  exit 3
fi
echo "[OK] py_compile ok" | tee -a "$OUT/log.txt"

# Restart
if command -v sudo >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

# Smoke: verify contract
echo "== [SMOKE] runs_v3 contract ==" | tee -a "$OUT/log.txt"
curl -fsS "$BASE/api/vsp/runs_v3?limit=5&include_ci=1" | python3 - <<'PY' | tee -a "$OUT/log.txt"
import sys, json
j=json.load(sys.stdin)
print("keys=", sorted(list(j.keys())))
items=j.get("items") or []
runs=j.get("runs") or []
print("items_len=", len(items) if isinstance(items,list) else type(items).__name__)
print("runs_len=", len(runs) if isinstance(runs,list) else type(runs).__name__)
print("total=", j.get("total"))
PY

echo "[OK] P4842 done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
