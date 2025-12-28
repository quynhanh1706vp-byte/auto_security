#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [A] route line =="
grep -nE 'add_url_rule\(.*/api/vsp/run_file_allow' -n "$W" | head -n 5 || true

FN="$(python3 - <<'PY'
import re
s=open("wsgi_vsp_ui_gateway.py","r",encoding="utf-8",errors="replace").read()
m=re.search(r'add_url_rule\(\s*["\']/api/vsp/run_file_allow["\']\s*,\s*["\'][^"\']+["\']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
if m:
  print(m.group(1)); raise SystemExit
# fallback: last def vsp_run_file_allow*
cands=re.findall(r'^\s*def\s+(vsp_run_file_allow\w*)\s*\(', s, flags=re.M)
print(cands[-1] if cands else "")
PY
)"

echo "== [B] detected function =="
echo "FN=$FN"
[ -n "${FN}" ] || { echo "[ERR] cannot detect handler function"; exit 2; }

echo "== [C] show handler block (first ~120 lines) =="
python3 - <<'PY'
import re
from pathlib import Path
fn=Path("wsgi_vsp_ui_gateway.py").read_text(encoding="utf-8",errors="replace").splitlines(True)
import sys
name=sys.argv[1]
# find def
di=None
for i,l in enumerate(fn):
  if re.match(r'^\s*def\s+'+re.escape(name)+r'\s*\(', l):
    di=i; break
if di is None:
  print("[ERR] cannot find def", name); raise SystemExit(2)
indent=len(fn[di]) - len(fn[di].lstrip(" "))
end=len(fn)
for j in range(di+1,len(fn)):
  lj=fn[j]
  if lj.strip()=="":
    continue
  if (len(lj)-len(lj.lstrip(" ")))==indent and (lj.lstrip().startswith("def ") or lj.lstrip().startswith("@")):
    end=j; break
block=fn[di:min(end, di+140)]
for k,l in enumerate(block, start=di+1):
  print(f"{k:6d}  {l.rstrip()}")
PY "$FN"

echo "== [D] show allow-check lines inside handler =="
python3 - <<'PY'
import re, sys
s=open("wsgi_vsp_ui_gateway.py","r",encoding="utf-8",errors="replace").read().splitlines()
fn=sys.argv[1]
# extract block quickly by indent
di=None
for i,l in enumerate(s):
  if re.match(r'^\s*def\s+'+re.escape(fn)+r'\s*\(', l):
    di=i; break
if di is None:
  print("[ERR] missing def"); raise SystemExit(2)
indent=len(s[di]) - len(s[di].lstrip(" "))
end=len(s)
for j in range(di+1,len(s)):
  lj=s[j]
  if lj.strip()=="":
    continue
  if (len(lj)-len(lj.lstrip(" ")))==indent and (lj.lstrip().startswith("def ") or lj.lstrip().startswith("@")):
    end=j; break
blk=s[di:end]
for idx,l in enumerate(blk, start=di+1):
  if "ALLOW" in l and ("not in" in l or "sorted(ALLOW)" in l or "allow" in l.lower()):
    print(f"{idx:6d}  {l}")
PY "$FN"
