#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fill_cwe_grype_${TS}" && echo "[BACKUP] $F.bak_fill_cwe_grype_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_FILL_CWE_FROM_RAW_GRYE_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# 1) Find handler function
m = re.search(r'(?m)^\s*def\s+api_vsp_findings_unified_v1\s*\(\s*rid\s*\)\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find def api_vsp_findings_unified_v1(rid): in wsgi")

# 2) Inject right AFTER: items=_apply_filters(...)
pat = re.compile(r'(\n\s*items\s*=\s*_apply_filters\([^\n]*\)\s*\n)')
mm = pat.search(s, pos=m.start())
if not mm:
    raise SystemExit("[ERR] cannot find items=_apply_filters(...) inside handler")

inject = mm.group(1) + r'''
    # === VSP_FILL_CWE_FROM_RAW_GRYE_V1 ===
    # Fill item.cwe from item.raw.vulnerability.cwes[*].cwe (GRYPE proven has this)
    debug_cwe_sample = None
    try:
      for _it in (items or []):
        if _it.get("cwe"):
          continue
        _tool = str(_it.get("tool") or "").upper()
        if _tool != "GRYPE":
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
          if debug_cwe_sample is None:
            debug_cwe_sample = _it["cwe"]
    except Exception:
      pass
    # === /VSP_FILL_CWE_FROM_RAW_GRYE_V1 ===

'''
s = s[:mm.start()] + inject + s[mm.end():]

# 3) Add debug field to response (only debug=1)
# We locate the return jsonify({ ... }) and inject "debug" key if not present.
# (keep it minimal; won't break UI)
ret_pat = re.compile(r'(?s)return\s+jsonify\(\s*\{\s*(.*?)\s*\}\s*\)\s*,\s*200')
rm = ret_pat.search(s, pos=m.start())
if not rm:
    raise SystemExit("[ERR] cannot find return jsonify({...}), 200 in handler")

body = rm.group(1)
if '"debug"' not in body:
    # inject near end: after "filters":...
    body2 = re.sub(
        r'("filters"\s*:\s*\{[^}]*\}\s*,?)',
        r'\1\n        "debug": ({"marker":"VSP_FILL_CWE_FROM_RAW_GRYE_V1","cwe_sample":debug_cwe_sample} if (request.args.get("debug")=="1") else None),',
        body,
        count=1
    )
    if body2 == body:
        # fallback: just append
        body2 = body + '\n        "debug": ({"marker":"VSP_FILL_CWE_FROM_RAW_GRYE_V1","cwe_sample":debug_cwe_sample} if (request.args.get("debug")=="1") else None),\n'
    s = s[:rm.start(1)] + body2 + s[rm.end(1):]

p.write_text(s, encoding="utf-8")
print("[OK] patched:", marker)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
