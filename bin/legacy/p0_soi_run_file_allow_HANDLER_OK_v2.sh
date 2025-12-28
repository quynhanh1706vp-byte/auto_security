#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [A] route => function =="
FN="$(python3 - <<'PY'
import re
s=open("wsgi_vsp_ui_gateway.py","r",encoding="utf-8",errors="replace").read()
m=re.search(r'add_url_rule\(\s*["\']/api/vsp/run_file_allow["\']\s*,\s*["\'][^"\']+["\']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
print(m.group(1) if m else "")
PY
)"
echo "FN=$FN"
[ -n "$FN" ] || { echo "[ERR] cannot detect handler"; exit 3; }

echo "== [B] key lines inside handler (ALLOW/rel/not allowed/run_gate) =="
python3 - <<PY
import re
from pathlib import Path
fn="${FN}"
lines=Path("wsgi_vsp_ui_gateway.py").read_text(encoding="utf-8",errors="replace").splitlines(True)

# find def
def_i=None
for i,l in enumerate(lines):
    if re.match(rf'^\\s*def\\s+{re.escape(fn)}\\s*\\(', l):
        def_i=i; break
if def_i is None:
    print("[ERR] def not found:", fn); raise SystemExit(2)

indent=re.match(r'^(\\s*)def\\s+', lines[def_i]).group(1)

end_i=len(lines)
for j in range(def_i+1,len(lines)):
    if re.match(rf'^{re.escape(indent)}(def\\s+|@)', lines[j]):
        end_i=j; break

block=lines[def_i:end_i]
for k,l in enumerate(block, start=def_i+1):
    if ("ALLOW" in l) or ("not allowed" in l) or (re.search(r'\\brel\\b\\s*=', l)) or ("run_gate" in l):
        print(f"{k:6d}: {l.rstrip()}")
PY

echo "== [C] show exact route mount line(s) =="
grep -nE 'add_url_rule\(.*/api/vsp/run_file_allow' -n "$W" | head -n 5 || true
