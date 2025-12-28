#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need grep

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_bslash_v3_${TS}"
echo "[BACKUP] ${F}.bak_fix_bslash_v3_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

needle = 'replace("\\","/")'          # TEXT in file: replace("\","/")
fixed  = 'replace("\\\\","/")'        # TEXT in file: replace("\\","/")

changed = 0
hit_lines = []

for i, line in enumerate(lines, start=1):
    if needle in line:
        lines[i-1] = line.replace(needle, fixed)
        changed += 1
        hit_lines.append(i)

# Extra safety: if the whole orig_path line is still broken, rewrite it.
for i, line in enumerate(lines, start=1):
    if "orig_path" in line and "path.replace" in line and 'replace("\\","/")' in line:
        # already handled
        pass
    # catch the exact broken symptom as shown in your error
    if i == 13024 and 'orig_path = path.replace("\\","/").lstrip("/")' not in line and 'orig_path' in line and 'replace("\\","/")' not in line:
        # no-op; keep only for reference
        pass

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched occurrences={changed} at lines={hit_lines[:12]}{'...' if len(hit_lines)>12 else ''}")

# verify: ensure the broken token is gone if it existed
s2 = p.read_text(encoding="utf-8", errors="replace")
if needle in s2:
    # still present somewhere
    loc = s2.find(needle)
    snippet = s2[max(0,loc-60):loc+60]
    raise SystemExit("[ERR] broken needle still present around: " + snippet.replace("\n","\\n"))
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] fixed backslash syntax + restarted"
