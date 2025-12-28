#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_cwe_enrich_demoapp_${TS}" && echo "[BACKUP] $F.bak_cwe_enrich_demoapp_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_DEMOAPP_CWE_ENRICH_P1_V4"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

helper = r'''
# === VSP_DEMOAPP_CWE_ENRICH_P1_V4 ===
def _vsp_norm_cwe_demo(x):
  try:
    x = str(x or "").strip()
    if not x: return None
    u = x.upper()
    if u.startswith("CWE-"): return u
    if x.isdigit(): return "CWE-" + x
    return u
  except Exception:
    return None

def _vsp_enrich_cwe_from_raw_demo(it):
  """Fill it['cwe'] from it['raw'] when missing. Focus: GRYPE."""
  try:
    if it.get("cwe"):
      return it
    raw = it.get("raw") or {}
    tool = (it.get("tool") or "").upper()
    if tool != "GRYPE":
      return it
    vuln = raw.get("vulnerability") or {}
    cwes = vuln.get("cwes") or []
    out=[]
    for c in cwes:
      if isinstance(c, dict):
        v = c.get("cwe")
      else:
        v = c
      nv = _vsp_norm_cwe_demo(v)
      if nv: out.append(nv)
    if out:
      it["cwe"] = list(dict.fromkeys(out))
  except Exception:
    pass
  return it
# === /VSP_DEMOAPP_CWE_ENRICH_P1_V4 ===
'''

# append helper near end (safe)
s = s.rstrip() + "\n\n" + helper + "\n"

# inject enrichment right after items filtered (inside api_vsp_findings_unified_v1)
pat = r'(\n\s*items\s*=\s*_apply_filters\([^\n]*\)\s*\n)'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find items=_apply_filters(...) in vsp_demo_app.py")

inject = m.group(1) + (
  "    # [P1] CWE enrich from raw (GRYPE) so top_cwe is real (not UNKNOWN)\n"
  "    try:\n"
  "      items = [_vsp_enrich_cwe_from_raw_demo(dict(it)) for it in items]\n"
  "    except Exception:\n"
  "      pass\n"
)
s = s[:m.start()] + inject + s[m.end():]

# also tweak counts loop to use cwe list correctly (replace old cwe extraction if present)
# (safe: only replace first matching old block)
old = re.compile(
  r'(?m)^\s*cw\s*=\s*it\.get\("cwe"\)\s*\n'
  r'^\s*c\s*=\s*"UNKNOWN"\s*\n'
  r'^\s*if\s+isinstance\(cw,\s*list\)\s+and\s+cw:\s*\n'
  r'^\s*\s*c\s*=\s*str\(cw\[0\]\s*or\s*"UNKNOWN"\)\.upper\(\)\s*\n'
  r'^\s*elif\s+isinstance\(cw,\s*str\)\s+and\s+cw\.strip\(\):\s*\n'
  r'^\s*\s*c\s*=\s*cw\.strip\(\)\.upper\(\)\s*\n'
)
mm = old.search(s)
if mm:
    rep = (
      "    cws = it.get('cwe')\n"
      "    c = 'UNKNOWN'\n"
      "    if isinstance(cws, list) and cws:\n"
      "      c = str(cws[0] or 'UNKNOWN').upper()\n"
      "    elif isinstance(cws, str) and cws.strip():\n"
      "      c = cws.strip().upper()\n"
    )
    s = s[:mm.start()] + rep + s[mm.end():]

# add a debug marker in response (only if debug=1)
# Insert before final return jsonify({...})
if "debug=request.args.get(\"debug\")" not in s:
    s = s.replace(
      '"filters": {"q": q, "sev": sev, "tool": tool, "cwe": cwe, "file": fileq},',
      '"filters": {"q": q, "sev": sev, "tool": tool, "cwe": cwe, "file": fileq},\n'
      '        "debug": ({"cwe_enrich":"P1_V4"} if (request.args.get("debug")=="1") else None),'
    )

p.write_text(s, encoding="utf-8")
print("[OK] patched:", marker)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
