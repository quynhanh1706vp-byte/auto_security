#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_cwe_enrich_${TS}" && echo "[BACKUP] $F.bak_cwe_enrich_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_CWE_ENRICH_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker); raise SystemExit(0)

# Insert helper near the findings api block marker
ins = r'''
# --- VSP_CWE_ENRICH_P1_V1 ---
def _enrich_cwe_item(it):
  """Best-effort CWE enrichment for UI grouping (non-invasive).
  - GRYPE: raw.relatedVulnerabilities[*].cwes[*].cwe or vulnerability.cwes[*].cwe
  - CODEQL: raw.rule.cwe / raw.cwe / raw.properties.cwe (varies)
  - KICS: keep UNKNOWN for now unless you provide mapping table
  """
  try:
    if it.get("cwe"):
      return it
    tool = (it.get("tool") or "").upper()
    raw = it.get("raw") or {}
    cwe = None

    if tool == "GRYPE":
      # prefer relatedVulnerabilities -> cwes
      rv = raw.get("relatedVulnerabilities") or []
      for v in rv:
        for c in (v.get("cwes") or []):
          cc = (c.get("cwe") or "").strip()
          if cc:
            cwe = cc; break
        if cwe: break
      if not cwe:
        for c in (raw.get("vulnerability") or {}).get("cwes") or []:
          cc = (c.get("cwe") or "").strip()
          if cc:
            cwe = cc; break

    elif tool == "CODEQL":
      # SARIF-derived: try common fields
      for path in [
        ("rule","properties","cwe"),
        ("rule","cwe"),
        ("cwe",),
        ("properties","cwe"),
      ]:
        cur = raw
        ok = True
        for k in path:
          if isinstance(cur, dict) and k in cur:
            cur = cur[k]
          else:
            ok = False; break
        if ok and cur:
          cwe = cur; break

    # normalize
    if isinstance(cwe, list) and cwe:
      cwe = cwe[0]
    if isinstance(cwe, str):
      cwe = cwe.strip()
      if cwe and not cwe.upper().startswith("CWE-"):
        # allow "79" -> "CWE-79"
        if cwe.isdigit():
          cwe = "CWE-" + cwe

    if cwe:
      it["cwe"] = [cwe]
  except Exception:
    pass
  return it
# --- /VSP_CWE_ENRICH_P1_V1 ---
'''

# place helper before counts computation inside the findings api block
# find the line 'by_sev={}; by_tool={}; by_cwe={}' and inject enrichment loop before it.
pat = r'(\n\s*by_sev=\{\};\s*by_tool=\{\};\s*by_cwe=\{\}\s*\n)'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find counts block (by_sev/by_tool/by_cwe)")

# add helper (once) near the top of file end to keep simple
s = s + "\n\n" + ins + "\n"

# inject enrichment usage: before counts loop, enrich all items
inject = "\n    # enrich CWE (best-effort)\n    try:\n      items = [_enrich_cwe_item(dict(it)) for it in items]\n    except Exception:\n      pass\n\n"
s = re.sub(pat, inject + r'\1', s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched CWE enrich helper + hook")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
