#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "$APP.bak_orphanindent_${TS}"
echo "[BACKUP] $APP.bak_orphanindent_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

TOP = re.compile(r'^(# ---|@app\.|def |class |if __name__)')

# Sentinels that appear in the orphan block you pasted
SENT = [
  'ctype = (getattr(resp, "mimetype"',
  '# grab existing cache-bust v=',
  'def keep_or_drop',
  'body2 = script_re.sub',
  'script_re = re.compile',
]

def find_orphan():
    for i, ln in enumerate(lines):
        if ln.startswith((" ", "\t")) and any(x in ln for x in SENT):
            # expand to full orphan block: go up until top-level marker
            a = i
            while a > 0 and not TOP.match(lines[a-1]):
                # stop if previous is clearly normal code at col0
                if lines[a-1] and not lines[a-1].startswith((" ", "\t")) and lines[a-1].strip():
                    break
                a -= 1
            # go down until next top-level marker
            b = i
            while b < len(lines) and not TOP.match(lines[b]):
                b += 1
            return a, b
    return None

removed = 0
while True:
    rng = find_orphan()
    if not rng:
        break
    a, b = rng
    # safety: only remove if block contains at least one sentinel
    block = "".join(lines[a:b])
    if not any(x in block for x in SENT):
        break
    del lines[a:b]
    removed += 1

p.write_text("".join(lines), encoding="utf-8")
print("[OK] removed_orphan_blocks=", removed)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
