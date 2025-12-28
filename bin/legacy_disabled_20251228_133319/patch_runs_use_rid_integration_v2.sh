#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

grep -q "VSP_USE_RID_INTEGRATION_V2" "$F" && { echo "[OK] already patched integration v2"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_userid_intv2_${TS}"
echo "[BACKUP] $F.bak_userid_intv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# inject helper once, near top after 'use strict' (best-effort)
marker = "/* VSP_USE_RID_INTEGRATION_V2 */"
if marker in s:
    print("[OK] marker already exists")
    raise SystemExit(0)

helper = r'''
  /* VSP_USE_RID_INTEGRATION_V2 */
  function vspSetRidUnified(rid){
    try {
      if(!rid) return;
      // best: use global setter from RID state v2 if present
      if (window && typeof window.VSP_SET_RID === 'function') {
        window.VSP_SET_RID(rid);
      } else {
        try { localStorage.setItem("VSP_CURRENT_RID", rid); } catch(e) {}
      }

      // update label immediately (no need to rely on storage event)
      try {
        var lab = document.getElementById("vsp-rid-label");
        if (lab) lab.textContent = "RID: " + rid;
      } catch(e) {}

      // notify others
      try {
        window.dispatchEvent(new CustomEvent("vsp:rid", { detail: { rid: rid } }));
      } catch(e) {}
    } catch(e) {}
  }
'''

# place helper after pickRunsPane() or after esc() - heuristic
pos = s.find("function pickRunsPane()")
if pos > 0:
    insert_at = s.rfind("\n", 0, pos)
    new = s[:insert_at] + helper + s[insert_at:]
else:
    # fallback: after 'use strict'
    new = re.sub(r"('use strict';\s*)", r"\1\n"+helper+"\n", s, count=1)

# now patch handler: when clicking Use RID, call vspSetRidUnified(rid)
# look for existing handler block comment "VSP_USE_RID_HANDLER_V1"
if "VSP_USE_RID_HANDLER_V1" not in new:
    # if handler not found, append a minimal delegation at end (safe)
    new += r'''
/* VSP_USE_RID_HANDLER_V1_FALLBACK */
document.addEventListener('click', function(ev){
  try{
    var t = ev && ev.target ? ev.target : null;
    if(!t) return;
    var btn = (t.closest ? t.closest('.vsp-use-rid') : null);
    if(!btn) return;
    var rid = btn.getAttribute('data-rid') || '';
    if(!rid) return;
    vspSetRidUnified(rid);
  }catch(e){}
});
'''
else:
    # ensure inside existing handler we call vspSetRidUnified(rid) after rid extracted
    # simple injection: after "var rid = ..." line, add call.
    new2 = re.sub(r"(var\s+rid\s*=\s*[^;]+;\s*)", r"\1\n      vspSetRidUnified(rid);\n", new, count=1)
    new = new2

p.write_text(new, encoding="utf-8")
print("[OK] patched Use RID integration v2")
PY

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_wait_v1.sh
