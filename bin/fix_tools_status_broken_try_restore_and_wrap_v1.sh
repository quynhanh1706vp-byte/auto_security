#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

JS="static/js/vsp_tools_status_from_gate_p0_v1.js"
TPL="templates/vsp_dashboard_2025.html"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

echo "== [1/5] find a GOOD backup that passes node --check =="
CANDS="$(ls -1t ${JS}.bak_guard_render_* ${JS}.bak_blankfix_* ${JS}.bak_nullfix_* 2>/dev/null || true)"
GOOD=""
for b in $CANDS; do
  if node --check "$b" >/dev/null 2>&1; then
    GOOD="$b"
    break
  fi
done
[ -n "${GOOD:-}" ] || { echo "[ERR] no good backup found for $JS"; echo "$CANDS"; exit 3; }
echo "[OK] picked GOOD backup: $GOOD"

echo "== [2/5] restore to GOOD backup =="
cp -f "$JS" "${JS}.bak_before_restore_${TS}" && echo "[BACKUP] ${JS}.bak_before_restore_${TS}"
cp -f "$GOOD" "$JS" && echo "[RESTORE] $JS <= $GOOD"

echo "== [3/5] inject dummy selectors (NO regex on textContent; safe with template literals) =="
python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_tools_status_from_gate_p0_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

if "__VSP_DUMMY_EL__" not in s:
    helper = r"""
  // __VSP_DUMMY_EL__: prevent null crashes when mounts are hidden/missing
  const __VSP_DUMMY_EL__ = {
    textContent:"", innerHTML:"", style:{},
    classList:{ add(){}, remove(){}, toggle(){} },
    setAttribute(){}, removeAttribute(){},
    appendChild(){}, prepend(){}, remove(){},
    querySelector(){ return null; }, querySelectorAll(){ return []; }
  };
  function __vsp_q(sel){
    try { return document.querySelector(sel) || __VSP_DUMMY_EL__; }
    catch(_) { return __VSP_DUMMY_EL__; }
  }
  function __vsp_id(id){
    try { return document.getElementById(id) || __VSP_DUMMY_EL__; }
    catch(_) { return __VSP_DUMMY_EL__; }
  }
"""
    m=re.search(r"(['\"]use strict['\"];)", s)
    if m:
        s = s[:m.end()] + helper + s[m.end():]
    else:
        s = helper + "\n" + s

# only rewrite the call-sites (do NOT touch .textContent assignments)
s = s.replace("document.querySelector(", "__vsp_q(")
s = s.replace("document.getElementById(", "__vsp_id(")

p.write_text(s, encoding="utf-8")
print("[OK] injected dummy selector helpers + rewired querySelector/getElementById")
PY

echo "== [4/5] wrap whole file in IIFE with route guard (safe return) =="
python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_tools_status_from_gate_p0_v1.js")
orig=p.read_text(encoding="utf-8", errors="ignore")
if "VSP_TOOLS_STATUS_ROUTE_GUARD_V1" in orig:
    print("[OK] already wrapped; skip")
    raise SystemExit(0)

head=f"""/* VSP_TOOLS_STATUS_ROUTE_GUARD_V1 */
(function(){{
  'use strict';
  function __vsp_is_runs(){{
    try {{
      const h=(location.hash||'').toLowerCase();
      return h.startsWith('#runs') || h.includes('#runs/');
    }} catch(e) {{ return false; }}
  }}
  function __vsp_policy_open(){{
    try {{
      const p=document.getElementById('vsp_policy_panel_v1') || document.getElementById('vsp_policy_panel');
      if(!p) return false;
      const d=(p.style && p.style.display) ? p.style.display : '';
      return d && d !== 'none';
    }} catch(e) {{ return false; }}
  }}
  // Only run on #runs OR when policy panel is opened
  if(!__vsp_is_runs() && !__vsp_policy_open()){{
    try{{ console.info('[VSP_TOOLS_STATUS_ROUTE_GUARD_V1] skip tools_status on', location.hash); }}catch(_e){{}}
    return;
  }}

"""
tail="\n})();\n"
p.write_text(head + orig + tail, encoding="utf-8")
print("[OK] wrapped tools_status with route guard")
PY

node --check "$JS" >/dev/null && echo "[OK] node --check tools_status" || { echo "[ERR] tools_status still broken"; node --check "$JS"; exit 4; }

echo "== [5/5] cachebust template so browser MUST load new tools_status =="
[ -f "$TPL" ] || { echo "[WARN] missing $TPL, skip cachebust"; exit 0; }
cp -f "$TPL" "$TPL.bak_cb_tools_${TS}" && echo "[BACKUP] $TPL.bak_cb_tools_${TS}"
python3 - <<PY
from pathlib import Path
import re
p=Path("$TPL")
s=p.read_text(encoding="utf-8", errors="ignore")
s = re.sub(r'(vsp_tools_status_from_gate_p0_v1\.js)(\?[^"\']*)?', r'\1?v=$TS', s)
p.write_text(s, encoding="utf-8")
print("[OK] cachebusted tools_status in template")
PY

echo "[DONE] Now restart UI + Ctrl+Shift+R + Ctrl+0."
