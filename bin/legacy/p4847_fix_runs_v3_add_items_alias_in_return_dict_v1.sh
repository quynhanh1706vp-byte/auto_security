#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4847_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

BK="$OUT/${APP}.bak_before_p4847_${TS}"
cp -f "$APP" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

anchor = "/api/vsp/runs_v3"
ai = s.find(anchor)
if ai < 0:
    raise SystemExit("[ERR] cannot find /api/vsp/runs_v3")

# window around the endpoint
win_start = max(0, ai - 2500)
win_end   = min(len(s), ai + 45000)
w = s[win_start:win_end]

MARK = "VSP_P4847_RUNS_V3_ITEMS_ALIAS"

# avoid double patch
if MARK in w:
    print("[OK] already patched P4847")
    raise SystemExit(0)

# target: return jsonify({... 'runs': <rhs> ...}) or return jsonify(_vsp_runs_v3_contract({...}))
# We inject 'items': <same rhs> right after runs.
def inject(txt: str):
    n = 0

    # double quotes key
    def repl(m):
        nonlocal n
        rhs = m.group(2).strip()
        # skip if already has items nearby
        span = m.group(0)
        if re.search(r'["\']items["\']\s*:', span):
            return span
        n += 1
        return f'{m.group(1)}{rhs}{m.group(3)} "items": {rhs},'

    # Match: "runs": <rhs>,
    txt2 = re.sub(
        r'("runs"\s*:\s*)([^,}\n]+)(\s*,)',
        repl,
        txt,
        count=1
    )

    if txt2 != txt:
        return txt2, n

    # single quotes key
    def repl2(m):
        nonlocal n
        rhs = m.group(2).strip()
        span = m.group(0)
        if re.search(r'["\']items["\']\s*:', span):
            return span
        n += 1
        return f"{m.group(1)}{rhs}{m.group(3)} 'items': {rhs},"

    txt3 = re.sub(
        r"('runs'\s*:\s*)([^,}\n]+)(\s*,)",
        repl2,
        txt,
        count=1
    )
    return txt3, n

# restrict to the return jsonify(...) area to reduce false matches
# find first "return jsonify" after anchor
mret = re.search(r'^\s*return\s+jsonify\s*\(', w, flags=re.M)
if not mret:
    raise SystemExit("[ERR] cannot find `return jsonify(` near runs_v3")

# operate from that return onward (still within window)
head = w[:mret.start()]
tail = w[mret.start():]

tail2, n = inject(tail)
if n == 0:
    # fallback: sometimes they build dict in one line with no comma right after runs; handle `runs: runs }`
    def repl3(m):
        rhs = m.group(2).strip()
        return f'{m.group(1)}{rhs}{m.group(3)} "items": {rhs}{m.group(4)}'
    tail2b = re.sub(r'("runs"\s*:\s*)([^,}\n]+)(\s*)(\})', repl3, tail, count=1)
    if tail2b != tail:
        tail2, n = tail2b, 1

if n == 0:
    raise SystemExit("[ERR] cannot inject items alias (pattern not found). Need manual inspect of runs_v3 return.")

# stamp marker near the patched return for audit
tail2 = re.sub(r'^\s*return\s+jsonify', lambda mm: f"# {MARK}\n" + mm.group(0), tail2, count=1, flags=re.M)

w2 = head + tail2
s2 = s[:win_start] + w2 + s[win_end:]
p.write_text(s2, encoding="utf-8")

print(f"[P4847] injected_items_alias={n}")
print("[OK] wrote vsp_demo_app.py")
PY

# compile gate
if ! python3 -m py_compile "$APP" 2> "$OUT/py_compile.err"; then
  echo "[ERR] py_compile failed; showing error:" | tee -a "$OUT/log.txt"
  sed -n '1,120p' "$OUT/py_compile.err" | tee -a "$OUT/log.txt"
  echo "[ERR] restoring backup..." | tee -a "$OUT/log.txt"
  cp -f "$BK" "$APP"
  exit 3
fi
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

echo "[OK] P4847 done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
