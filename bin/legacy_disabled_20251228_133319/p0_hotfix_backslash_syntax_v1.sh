#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need sed; need grep

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_hotfix_bslash_${TS}"
echo "[BACKUP] ${W}.bak_hotfix_bslash_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

if 'VSP_P1_WSGI_MW_GATE_FILENAME_V1' not in s:
    raise SystemExit("[ERR] marker VSP_P1_WSGI_MW_GATE_FILENAME_V1 not found")

bad = 'path.replace("\\","/")'          # this is what we WANT in file (two slashes in literal)
# but file currently contains: path.replace("\","/")  (invalid) -> it appears as: path.replace("\","/)
# We fix by replacing the exact broken sequence as text:
broken = 'path.replace("\\","/")'  # placeholder, will not match
# Instead: search for the specific bad pattern that includes backslash then quote.
# We'll do a safe manual fix around 'orig_path ='
old_snip = 'orig_path = path.replace("\\","/").lstrip("/")'  # desired
if old_snip in s:
    print("[OK] already fixed line")
    raise SystemExit(0)

# Fix the broken line (as it appears in the file: backslash before quote)
s2 = s.replace('orig_path = path.replace("\\","/").lstrip("/")', old_snip)

# If the above didn't work (because it is syntactically broken), fix via a looser replace:
if s2 == s:
    s2 = s.replace('orig_path = path.replace("\\","/").lstrip("/")', old_snip)

# Ultimate fallback: replace the exact broken token sequence: replace("\","/)
if s2 == s:
    s2 = s.replace('replace("\\","/")', 'replace("\\\\","/")')  # no-op guard (won't happen)
if s2 == s:
    s2 = s.replace('replace("\\","/")', 'replace("\\\\","/")')

# The real broken text is: replace("\","/)
# We can’t write that literally in a Python string without escaping, so build it:
broken_token = 'replace("' + '\\' + '","/")'  # yields replace("\","/") as text
s2 = s2.replace(broken_token, 'replace("\\\\","/")')  # this writes replace("\\","/") into file

# Now ensure we ended up with correct code (contains replace("\\","/"))
if 'replace("\\\\","/")' not in s2 and 'replace("\\","/")' not in s2:
    # Force-set the whole orig_path line if still broken
    import re
    s2 = re.sub(r'orig_path\s*=\s*path\.replace\([^\n]*\)\.lstrip\(["\']\/["\']\)',
                'orig_path = path.replace("\\\\","/").lstrip("/")',
                s2)

p.write_text(s2, encoding="utf-8")
print("[OK] hotfixed backslash literal in middleware block")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.7
echo "[OK] restarted (or attempted)"
