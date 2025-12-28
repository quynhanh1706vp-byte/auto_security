#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_cwe_safe_${TS}" && echo "[BACKUP] $F.bak_cwe_safe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_CWE_SAFE_GRYE_V2"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# 1) Inject CWE fill right after items=_apply_filters(...) (NO touching return/jsonify)
pat = re.compile(r'(\n\s*items\s*=\s*_apply_filters\([^\n]*\)\s*\n)')
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find items=_apply_filters(...)")

inject = m.group(1) + r'''
    # === VSP_CWE_SAFE_GRYE_V2 ===
    # Fill item.cwe from item.raw.vulnerability.cwes[*].cwe (GRYPE)
    try:
      for _it in (items or []):
        if _it.get("cwe"):
          continue
        if str(_it.get("tool") or "").upper() != "GRYPE":
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
    # === /VSP_CWE_SAFE_GRYE_V2 ===

'''

s = s[:m.start()] + inject + s[m.end():]

# 2) Make top_cwe exclude UNKNOWN (UNKNOWN will dominate otherwise)
# Replace common line: top_cwe=sorted(by_cwe.items(), key=lambda kv: kv[1], reverse=True)[:10]
s2 = s.replace(
  'top_cwe=sorted(by_cwe.items(), key=lambda kv: kv[1], reverse=True)[:10]',
  'unknown_count = by_cwe.get("UNKNOWN", 0)\n'
  '    top_cwe = sorted([(k,v) for (k,v) in by_cwe.items() if k!="UNKNOWN"], key=lambda kv: kv[1], reverse=True)[:10]'
)

# If pattern not found, do a regex fallback
if s2 == s:
  s2 = re.sub(
    r'(?m)^\s*top_cwe\s*=\s*sorted\(by_cwe\.items\(\),\s*key=lambda\s+kv:\s*kv\[1\],\s*reverse=True\)\s*\[:10\]\s*$',
    '    unknown_count = by_cwe.get("UNKNOWN", 0)\n'
    '    top_cwe = sorted([(k,v) for (k,v) in by_cwe.items() if k!="UNKNOWN"], key=lambda kv: kv[1], reverse=True)[:10]',
    s2,
    count=1
  )

# 3) Ensure unknown_count is returned (non-breaking: add if counts dict has no such key)
# Replace '"top_cwe": top_cwe,' with '"top_cwe": top_cwe, "unknown_count": unknown_count,'
s3 = s2.replace('"top_cwe": top_cwe,', '"top_cwe": top_cwe, "unknown_count": unknown_count,')

p.write_text(s3, encoding="utf-8")
print("[OK] patched:", marker)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
