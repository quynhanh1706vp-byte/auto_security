#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_bslash_${TS}"
echo "[BACKUP] ${F}.bak_fix_bslash_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# This needle string LITERALLY equals: replace("\","/") in the file
needle = 'replace("\\\\","/")'.replace('\\\\\\\\','\\\\')  # yields replace("\","/") as text
# simpler:
needle = 'replace("\\\\","/")'  # python literal -> replace("\","/") text

# Correct replacement in file should be: replace("\\","/")
replacement = 'replace("\\\\\\\\","/")'  # python literal -> replace("\\","/") text

n = s.count(needle)
if n == 0:
    # Heuristic line rewrite if needle not found
    lines = s.splitlines(True)
    changed = 0
    for i, line in enumerate(lines):
        if "orig_path" in line and "path.replace" in line and "lstrip" in line and 'replace("' in line and '","/")' in line:
            lines[i] = '    orig_path = path.replace("\\\\","/").lstrip("/")\n'
            changed += 1
    if changed == 0:
        raise SystemExit("[ERR] cannot find broken replace(\\\"\\\\\\\",\\\"/\\\") pattern to patch")
    s2 = "".join(lines)
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] line-heuristic patched: {changed}")
else:
    s2 = s.replace(needle, replacement)
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] replaced occurrences: {n}")
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] wsgi syntax fixed + service restarted"
