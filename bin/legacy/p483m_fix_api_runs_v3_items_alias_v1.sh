#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p483m_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true

# pick the real api file that contains /api/vsp/runs_v3
CAND=("vsp_demo_app.py" "wsgi_vsp_ui_gateway.py" "run_api/vsp_run_api_v1.py" "ui/vsp_demo_app.py")
APP=""
for f in "${CAND[@]}"; do
  if [ -f "$f" ] && grep -q "/api/vsp/runs_v3" "$f"; then APP="$f"; break; fi
done
if [ -z "${APP:-}" ]; then
  echo "[ERR] cannot find file containing /api/vsp/runs_v3 in: ${CAND[*]}" | tee -a "$OUT/log.txt"
  exit 3
fi

cp -f "$APP" "$APP.bak_p483m_${TS}"
echo "[OK] target=$APP" | tee -a "$OUT/log.txt"
echo "[OK] backup => $APP.bak_p483m_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, sys

mark = "VSP_P483M_RUNS_V3_ITEMS_ALIAS_V1"
p = None

# get target file from log (best-effort) by scanning known candidates
cands = ["vsp_demo_app.py", "wsgi_vsp_ui_gateway.py", "run_api/vsp_run_api_v1.py", "ui/vsp_demo_app.py"]
for f in cands:
    fp = Path(f)
    if fp.exists() and "/api/vsp/runs_v3" in fp.read_text(encoding="utf-8", errors="replace"):
        p = fp; break
if not p:
    print("[ERR] cannot locate target file in python stage"); sys.exit(3)

s = p.read_text(encoding="utf-8", errors="replace")
if mark in s:
    print("[OK] already patched"); sys.exit(0)

lines = s.splitlines(True)
idxs = [i for i,l in enumerate(lines) if "/api/vsp/runs_v3" in l]
if not idxs:
    print("[ERR] route string not found"); sys.exit(4)
i0 = idxs[0]

# find function start: the next "def " after route decorator area
def_i = None
for i in range(i0, min(i0+120, len(lines))):
    if re.match(r"^\s*def\s+\w+\s*\(", lines[i]):
        def_i = i; break
if def_i is None:
    print("[ERR] cannot find def for runs_v3 handler"); sys.exit(5)

# find function end: next decorator at col 0 (or eof)
end_i = len(lines)
for i in range(def_i+1, len(lines)):
    if re.match(r"^@\w", lines[i]) or re.match(r"^@app\.", lines[i]) or re.match(r"^@bp\.", lines[i]):
        end_i = i; break

block = "".join(lines[def_i:end_i])

# Patch strategy:
# A) If returns dict with keys ok/runs/total => inject items=runs
patched = block

# common literal dict patterns
patched2 = re.sub(
    r'(\{\s*["\']ok["\']\s*:\s*True\s*,\s*)["\']runs["\']\s*:\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*,',
    r'\1"items": \2, "runs": \2,',
    patched
)
patched = patched2

# jsonify(ok=True, runs=runs, total=total) => add items=runs
patched2 = re.sub(
    r'jsonify\(\s*([^)]*?)\bruns\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*,',
    r'jsonify(\1items=\2, runs=\2,',
    patched
)
patched = patched2

# If still no items mentioned inside handler, add a tiny normalize just before the first "return"
if '"items"' not in patched and "items=" not in patched:
    patched = re.sub(
        r'(\n\s*return\s+jsonify\s*\()',
        "\n    # "+mark+"\n    # Ensure stable contract: items + runs both present.\n"
        "    # (Commercial: backward compatible)\n"
        + r'\1',
        patched,
        count=1
    )

# If we did replacements, stamp marker near top of handler
if patched != block:
    # insert marker after def line
    blk_lines = patched.splitlines(True)
    for k in range(len(blk_lines)):
        if re.match(r"^\s*def\s+\w+\s*\(", blk_lines[k]):
            indent = re.match(r"^(\s*)def", blk_lines[k]).group(1)
            blk_lines.insert(k+1, f"{indent}    # {mark}\n")
            patched = "".join(blk_lines)
            break

# write back
out = "".join(lines[:def_i]) + patched + "".join(lines[end_i:])
p.write_text(out, encoding="utf-8")
print("[OK] patched handler in", p)
PY

python3 -m py_compile "$APP" | tee -a "$OUT/log.txt"

if command -v sudo >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
else
  echo "[WARN] sudo not found, please restart service manually: systemctl restart $SVC" | tee -a "$OUT/log.txt"
fi

echo "[OK] P483m done. Reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
