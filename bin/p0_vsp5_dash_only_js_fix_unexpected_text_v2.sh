#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fixtext_v2_${TS}"
echo "[BACKUP] ${JS}.bak_fixtext_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dash_only_v1.js")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

def is_commented(l: str) -> bool:
    s = l.lstrip()
    return s.startswith("//") or s.startswith("/*") or s.startswith("*") or s.startswith("*/")

def comment_line(l: str) -> str:
    # keep indentation
    m = re.match(r"^(\s*)(.*)$", l.rstrip("\n"))
    return f"{m.group(1)}// {m.group(2)}\n"

changed = 0

# 1) comment stray prose lines we already saw
prose_patterns = [
    r"Hook button",
    r"to fetch findings_unified\.json",
    r"on-demand and render table",
]

for i, l in enumerate(lines):
    if is_commented(l): 
        continue
    if any(re.search(pat, l) for pat in prose_patterns):
        lines[i] = comment_line(l)
        changed += 1

# 2) comment bullet lines like: "- NO auto-fetch heavy data"
# rule: line starts with optional spaces, then "- " then a LETTER (A-Z/a-z)
bullet_re = re.compile(r"^\s*-\s*[A-Za-z].*")
for i, l in enumerate(lines):
    if is_commented(l):
        continue
    if bullet_re.match(l):
        lines[i] = comment_line(l)
        changed += 1

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] commented injected/bullet lines: {changed}")
PY

echo "== [1] node --check after fix =="
node --check "$JS"

echo "== [2] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). SyntaxError must be gone."
