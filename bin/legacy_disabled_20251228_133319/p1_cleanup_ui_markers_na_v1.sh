#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need find

TS="$(date +%Y%m%d_%H%M%S)"
echo "== [1] Find offenders (TODO/FIXME/DEBUG/N/A) =="
OFF="/tmp/vsp_ui_offenders_${TS}.txt"
: > "$OFF"

# focus on shipped UI assets
find static templates -type f \( -name '*.js' -o -name '*.html' -o -name '*.css' \) -print0 \
| xargs -0 grep -RIn --line-number -E 'TODO|FIXME|DEBUG|["'"'"']N/A["'"'"']|\bN/A\b' \
| tee "$OFF" || true

echo
echo "Offenders list saved: $OFF"
echo "== [2] Auto-fix JS only (safe) =="
python3 - <<'PY'
import re, shutil, time
from pathlib import Path

root = Path(".")
ts = time.strftime("%Y%m%d_%H%M%S")
targets = list((root/"static").rglob("*.js"))

def backup(p: Path):
    b = p.with_suffix(p.suffix + f".bak_clean_{ts}")
    shutil.copy2(p, b)
    return b

changed = 0
for p in targets:
    s = p.read_text(encoding="utf-8", errors="replace")
    orig = s

    # 1) remove lines that are comment-only and contain TODO/FIXME/DEBUG
    #    (keeps real code; only strips noisy comment lines)
    lines = s.splitlines(True)
    new_lines = []
    for ln in lines:
        # strip only if it's a comment line (// ... or /* ... */ or * ... in block)
        if re.search(r'(TODO|FIXME|DEBUG)', ln) and re.match(r'^\s*(//|/\*|\*|\*/)', ln):
            continue
        new_lines.append(ln)
    s = "".join(new_lines)

    # 2) replace string literals "N/A" or 'N/A' -> em dash
    s = re.sub(r'(["\'])N/A\1', r'\1—\1', s)

    if s != orig:
        backup(p)
        p.write_text(s, encoding="utf-8")
        changed += 1

print(f"[OK] patched_files={changed} (backups: *.bak_clean_{ts})")
PY

echo "== [3] Verify remaining markers (should be minimal) =="
grep -RIn --line-number -E 'TODO|FIXME|DEBUG|["'"'"']N/A["'"'"']|\bN/A\b' static/js templates static/css | head -n 80 || true
echo "[DONE]"
