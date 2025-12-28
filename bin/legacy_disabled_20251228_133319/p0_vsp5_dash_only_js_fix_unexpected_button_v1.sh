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
cp -f "$JS" "${JS}.bak_fixbutton_${TS}"
echo "[BACKUP] ${JS}.bak_fixbutton_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dash_only_v1.js")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

def is_commented(l: str) -> bool:
    s = l.lstrip()
    return s.startswith("//") or s.startswith("/*") or s.startswith("*")

def comment_line(l: str) -> str:
    m = re.match(r"^(\s*)(.*)$", l.rstrip("\n"))
    return f"{m.group(1)}// {m.group(2)}\n"

changed = 0
for i, l in enumerate(lines):
    # Fix the exact offending human-text line that got injected
    if ("Hook button" in l) and (not is_commented(l)):
        lines[i] = comment_line(l)
        changed += 1

# Extra safety: if the line was wrapped/duplicated without "Hook button" keyword,
# also comment obvious injected prose about "to fetch findings_unified" if present.
for i, l in enumerate(lines):
    if ("to fetch findings_unified.json" in l or "on-demand and render table" in l) and (not is_commented(l)):
        lines[i] = comment_line(l)
        changed += 1

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] commented injected prose lines: {changed}")
PY

echo "== [1] node --check after fix =="
node --check "$JS"

echo "== [2] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). SyntaxError must be gone."
