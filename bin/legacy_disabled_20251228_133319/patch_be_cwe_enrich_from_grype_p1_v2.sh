#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_cwe_grype_${TS}" && echo "[BACKUP] $F.bak_cwe_grype_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_CWE_ENRICH_FROM_GRYPE_P1_V2"
if marker in s:
    print("[SKIP] marker exists:", marker); raise SystemExit(0)

helper = r'''
# --- VSP_CWE_ENRICH_FROM_GRYPE_P1_V2 ---
import re as _re

_CVE_RE = _re.compile(r'(CVE-\d{4}-\d+)', _re.I)

def _build_grype_cwe_map(run_dir):
  """Return {CVE-xxxx-yyy: [CWE-79, ...]} from run_dir/grype/grype.json if exists."""
  try:
    fp = os.path.join(run_dir, "grype", "grype.json")
    j = _read_json(fp)
    if not j or not isinstance(j, dict):
      return {}
    out = {}
    for m in (j.get("matches") or []):
      vuln = (m.get("vulnerability") or {})
      vid = (vuln.get("id") or "").strip()
      if not vid:
        continue
      cwes = []
      for c in (vuln.get("cwes") or []):
        cwe = (c.get("cwe") or "").strip()
        if cwe:
          if not cwe.upper().startswith("CWE-") and cwe.isdigit():
            cwe = "CWE-" + cwe
          cwes.append(cwe)
      if cwes:
        out[vid.upper()] = list(dict.fromkeys(cwes))
    return out
  except Exception:
    return {}

def _maybe_set_cwe_from_grype(it, grype_map):
  if it.get("cwe"):
    return it
  tool = (it.get("tool") or "").upper()
  if tool != "GRYPE":
    return it
  cand = (it.get("id") or "").strip()
  if not cand:
    # try parse CVE from title
    t = (it.get("title") or "")
    m = _CVE_RE.search(t or "")
    cand = m.group(1) if m else ""
  cand = (cand or "").upper()
  if cand and cand in grype_map:
    it["cwe"] = grype_map[cand]
  return it
# --- /VSP_CWE_ENRICH_FROM_GRYPE_P1_V2 ---
'''

# append helper at end (safe)
s = s.rstrip() + "\n\n" + helper + "\n"

# inject into api_vsp_findings_unified_v1 just after data loaded and filters applied:
# find line: items=_apply_filters(...)
pat = r'(items\s*=\s*_apply_filters\([^\n]*\)\s*\n)'
m = re.search(pat, s)
if not m:
    raise SystemExit("[ERR] cannot find items=_apply_filters(...) line in findings api")

inject = (
  m.group(1) +
  "    # enrich CWE from GRYPE raw file (safe; unified items may not carry raw)\n"
  "    grype_map = _build_grype_cwe_map(run_dir)\n"
  "    if grype_map:\n"
  "      try:\n"
  "        items = [_maybe_set_cwe_from_grype(dict(it), grype_map) for it in items]\n"
  "      except Exception:\n"
  "        pass\n"
)
s = s[:m.start()] + inject + s[m.end():]

p.write_text(s, encoding="utf-8")
print("[OK] patched:", marker)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
