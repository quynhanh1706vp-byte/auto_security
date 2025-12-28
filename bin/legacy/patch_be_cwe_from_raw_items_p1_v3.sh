#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_cwe_from_raw_${TS}" && echo "[BACKUP] $F.bak_cwe_from_raw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_CWE_FROM_RAW_ITEMS_P1_V3"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

helper = r'''
# --- VSP_CWE_FROM_RAW_ITEMS_P1_V3 ---
def _vsp_norm_cwe(x):
  try:
    x = str(x or "").strip()
    if not x:
      return None
    u = x.upper()
    if u.startswith("CWE-"):
      return u
    if x.isdigit():
      return "CWE-" + x
    return u
  except Exception:
    return None

def _vsp_extract_cwe_list(it):
  """Best-effort CWE extraction from unified item or item.raw.
  Works for GRYPE (raw.vulnerability.cwes) and some SARIF/CodeQL shapes.
  """
  try:
    # 1) already normalized in item.cwe
    cw = it.get("cwe")
    if isinstance(cw, list) and cw:
      out=[]
      for v in cw:
        nv=_vsp_norm_cwe(v)
        if nv: out.append(nv)
      if out: return list(dict.fromkeys(out))
    if isinstance(cw, str) and cw.strip():
      nv=_vsp_norm_cwe(cw)
      return [nv] if nv else None

    raw = it.get("raw") or {}

    # 2) GRYPE: raw.vulnerability.cwes[*].cwe
    vuln = raw.get("vulnerability") or {}
    cwes = vuln.get("cwes") or []
    out=[]
    for c in cwes:
      if isinstance(c, dict):
        nv=_vsp_norm_cwe(c.get("cwe"))
      else:
        nv=_vsp_norm_cwe(c)
      if nv: out.append(nv)
    if out: return list(dict.fromkeys(out))

    # 3) relatedVulnerabilities[*].cwes[*].cwe (some feeds)
    rv = raw.get("relatedVulnerabilities") or []
    out=[]
    for v in rv:
      for c in (v.get("cwes") or []):
        nv=_vsp_norm_cwe((c.get("cwe") if isinstance(c, dict) else c))
        if nv: out.append(nv)
    if out: return list(dict.fromkeys(out))

    # 4) SARIF-ish: raw.rule.properties.cwe or raw.properties.cwe
    for path in [
      ("rule","properties","cwe"),
      ("properties","cwe"),
      ("rule","cwe"),
      ("cwe",),
    ]:
      cur = raw
      ok=True
      for k in path:
        if isinstance(cur, dict) and k in cur:
          cur = cur[k]
        else:
          ok=False; break
      if ok and cur:
        if isinstance(cur, list) and cur:
          nv=_vsp_norm_cwe(cur[0])
          return [nv] if nv else None
        nv=_vsp_norm_cwe(cur)
        return [nv] if nv else None
  except Exception:
    pass
  return None
# --- /VSP_CWE_FROM_RAW_ITEMS_P1_V3 ---
'''

s = s.rstrip() + "\n\n" + helper + "\n"

# Replace the old "cw=it.get('cwe')..." normalization block inside the counts loop
pat = re.compile(
    r'(?m)^(?P<indent>\s*)cw=it\.get\("cwe"\);\s*c="UNKNOWN"\s*\n'
    r'(?P=indent)if isinstance\(cw,list\) and cw: c=str\(cw\[0\] or "UNKNOWN"\)\.upper\(\)\s*\n'
    r'(?P=indent)elif isinstance\(cw,str\) and cw\.strip\(\): c=cw\.strip\(\)\.upper\(\)\s*\n'
)

m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find old cwe normalization block (cw=it.get('cwe')...)")

ind = m.group("indent")
rep = (
    f"{ind}cws = _vsp_extract_cwe_list(it)\n"
    f"{ind}if cws and not it.get('cwe'):\n"
    f"{ind}  it['cwe'] = cws\n"
    f"{ind}c = (str(cws[0]).upper() if cws else 'UNKNOWN')\n"
)

s = pat.sub(rep, s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched:", marker)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
