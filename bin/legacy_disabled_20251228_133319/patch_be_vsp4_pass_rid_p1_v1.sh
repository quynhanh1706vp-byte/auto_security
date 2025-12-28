#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_pass_rid_${TS}" && echo "[BACKUP] $F.bak_pass_rid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_VSP4_PASS_RID_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# ensure helper exists
helper = r'''
# === VSP_VSP4_PASS_RID_P1_V1 ===
def _vsp_pick_latest_rid_best_effort():
  try:
    # local call to our own API endpoint logic: use filesystem resolved index route if available
    # Fallback to empty if anything fails.
    items = []
    try:
      # call function directly if defined (avoid HTTP)
      if "api_vsp_runs_index_v3_fs_resolved" in globals():
        j = api_vsp_runs_index_v3_fs_resolved()
        if isinstance(j, dict):
          items = j.get("items") or []
      elif "api_vsp_runs_index_v3_fs_resolved_v1" in globals():
        j = api_vsp_runs_index_v3_fs_resolved_v1()
        if isinstance(j, dict):
          items = j.get("items") or []
    except Exception:
      items = []
    if items:
      rid = (items[0].get("run_id") or items[0].get("rid") or "").strip()
      return rid
  except Exception:
    pass
  return ""
'''

# append helper near top (after imports)
if "_vsp_pick_latest_rid_best_effort" not in s:
    # put after first occurrence of "app =" or "application =" to keep scope in module
    m = re.search(r'(?m)^\s*(app|application)\s*=\s*', s)
    if m:
        s = s[:m.start()] + helper + "\n" + s[m.start():]
    else:
        s = helper + "\n" + s

# patch vsp4 handler to pass rid=...
# find render_template("vsp_4tabs_commercial_v1.html", ...)
pat = re.compile(r'render_template\s*\(\s*["\']vsp_4tabs_commercial_v1\.html["\']\s*(,\s*[^)]*)?\)', re.M)
mm = pat.search(s)
if not mm:
    raise SystemExit("[ERR] cannot find render_template('vsp_4tabs_commercial_v1.html', ...) in wsgi")

orig = mm.group(0)

# If rid already passed, skip
if re.search(r'\brid\s*=', orig):
    s = s.replace(orig, orig + "\n# " + marker)
else:
    # insert rid param before closing )
    repl = orig[:-1] + (", " if orig.endswith(")") and "," not in orig else ", ") + "rid=_vsp_pick_latest_rid_best_effort()" + ")"
    repl = repl + "\n# " + marker
    s = s[:mm.start()] + repl + s[mm.end():]

p.write_text(s, encoding="utf-8")
print("[OK] patched vsp4 render_template pass rid (best-effort)")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
