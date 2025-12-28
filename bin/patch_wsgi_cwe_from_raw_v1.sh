#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_cwe_raw_${TS}" && echo "[BACKUP] $F.bak_cwe_raw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_CWE_ENRICH_FROM_ITEM_RAW_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# Insert just after: items=_apply_filters(...)
pat = r'(\n\s*items\s*=\s*_apply_filters\([^\n]*\)\s*\n)'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find items=_apply_filters(...) in findings api")

inject = m.group(1) + r'''
    # === VSP_CWE_ENRICH_FROM_ITEM_RAW_V1 ===
    # Fill item.cwe from item.raw.vulnerability.cwes[*].cwe (GRYPE proven has this)
    try:
      for _it in items or []:
        if _it.get("cwe"):
          continue
        _raw = _it.get("raw") or {}
        _vuln = _raw.get("vulnerability") or {}
        _cwes = _vuln.get("cwes") or []
        _out = []
        for _c in _cwes:
          _v = _c.get("cwe") if isinstance(_c, dict) else _c
          if not _v:
            continue
          _v = str(_v).strip()
          if not _v:
            continue
          if (not _v.upper().startswith("CWE-")) and _v.isdigit():
            _v = "CWE-" + _v
          _out.append(_v.upper())
        if _out:
          _it["cwe"] = list(dict.fromkeys(_out))
    except Exception:
      pass
    # === /VSP_CWE_ENRICH_FROM_ITEM_RAW_V1 ===

'''

s = s[:m.start()] + inject + s[m.end():]
p.write_text(s, encoding="utf-8")
print("[OK] patched:", marker)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
