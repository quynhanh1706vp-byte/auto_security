#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

CTRL="static/js/vsp_commercial_layout_controller_v1.js"
[ -f "$CTRL" ] || { echo "[ERR] missing $CTRL"; exit 2; }
cp -f "$CTRL" "$CTRL.bak_v3_${TS}" && echo "[BACKUP] $CTRL.bak_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_commercial_layout_controller_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# 1) Make heading matcher fuzzy: allow "8 Tools Status", "Degraded tools (GREEN)", etc.
# Replace the isHeadingMatch function body to use contains()
pat = re.compile(r"function\s+isHeadingMatch\s*\([^)]*\)\s*\{.*?\}\s*", re.S)
m = pat.search(s)
if not m:
    print("[ERR] cannot find isHeadingMatch() to patch")
    raise SystemExit(2)

replacement = r"""function isHeadingMatch(text){
    const t=(text||"").trim().toUpperCase();
    if(!t) return false;
    // fuzzy: match if heading contains any target phrase (supports "8 TOOLS STATUS", "DEGRADED TOOLS (GREEN)", etc.)
    return HEADINGS.some(h=>t===h || t.startsWith(h) || t.includes(h));
  }
"""
s = s[:m.start()] + replacement + s[m.end():]

# 2) Add a small helper: detect if policy panel is open
if "__vspPolicyPanelOpen" not in s:
    inject = r"""
  function __vspPolicyPanelOpen(){
    try{
      const p = document.getElementById("vsp_policy_panel_v1");
      if(!p) return false;
      const d = (p.style && p.style.display) ? p.style.display : "";
      return d && d !== "none";
    }catch(_){ return false; }
  }
"""
    # inject after HEADINGS const or near top (best-effort)
    s = s.replace("const HEADINGS = [", inject + "\n  const HEADINGS = [", 1)

# 3) Stronger: on non-runs, also hide any element whose text contains "Tools Status" (even if not wrapped)
if "TOOLS STATUS\")))" not in s:
    # insert into hideRunsStripOutsideRuns() right after it computes isRuns
    s = s.replace(
        "const isRuns = (state.route===\"runs\" || state.route.startsWith(\"runs/\"));",
        "const isRuns = (state.route===\"runs\" || state.route.startsWith(\"runs/\"));\n"
        "    // extra: hide any 'Tools Status' strip on non-runs\n"
        "    if(!isRuns){\n"
        "      Array.from(document.querySelectorAll('div,span,h1,h2,h3,h4'))\n"
        "        .filter(n => ((n.textContent||'').toUpperCase().includes('TOOLS STATUS')))\n"
        "        .slice(0,18)\n"
        "        .forEach(n=>{\n"
        "          const wrap = n.closest('.vsp-card,.dashboard-card,.card,.panel,.box,section,article,header,div') || n;\n"
        "          wrap.style.display='none';\n"
        "        });\n"
        "    }\n",
        1
    )

p.write_text(s, encoding="utf-8")
print("[OK] patched controller fuzzy heading + stronger tools-status hide")
PY

# 4) Stop polling spam outside #runs by patching known scripts (best effort, safe-guard)
python3 - <<'PY'
from pathlib import Path
import re, time

def patch_guard(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="ignore")
    orig = s
    # insert guard near top after 'use strict' or first line
    guard = r"""
  function __vsp_is_runs(){
    try{
      const h = (location.hash||"").toLowerCase();
      return h.startsWith("#runs") || h.includes("#runs/");
    }catch(_){ return false; }
  }
  function __vsp_policy_open(){
    try{
      const p=document.getElementById("vsp_policy_panel_v1");
      return !!(p && p.style && p.style.display && p.style.display!=="none");
    }catch(_){ return false; }
  }
  // If not on runs and policy panel is closed => don't poll/render
  if(!__vsp_is_runs() && !__vsp_policy_open()){
    console.info("[VSP_COMMERCIAL_GUARD] skip non-runs render/poll:", location.hash, "%s");
    return;
  }
"""
    if "[VSP_COMMERCIAL_GUARD]" in s:
        return False

    if "'use strict';" in s:
        s = s.replace("'use strict';", "'use strict';\n" + guard.replace("%s", fp.name), 1)
    else:
        s = guard.replace("%s", fp.name) + "\n" + s

    if s != orig:
        bak = fp.with_suffix(fp.suffix + f".bak_guard_{time.strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(orig, encoding="utf-8")
        fp.write_text(s, encoding="utf-8")
        print("[OK] guarded", fp.name, "backup=>", bak.name)
        return True
    return False

targets = [
  Path("static/js/vsp_tool_pills_verdict_from_gate_p0_v1.js"),
  Path("static/js/vsp_tool_pills_verdict_from_gate_p0_v2.js"),
  Path("static/js/vsp_degraded_panel_hook_v3.js"),
  Path("static/js/vsp_tools_status_from_gate_p0_v1.js"),
]

patched = 0
for t in targets:
    if t.exists():
        if patch_guard(t):
            patched += 1

print("[DONE] guarded files =", patched)
PY

node --check static/js/vsp_commercial_layout_controller_v1.js >/dev/null 2>&1 && echo "[OK] node --check controller" || echo "[WARN] node --check controller failed"
echo "[DONE] V3 applied. Restart UI + Ctrl+Shift+R + Ctrl+0"
