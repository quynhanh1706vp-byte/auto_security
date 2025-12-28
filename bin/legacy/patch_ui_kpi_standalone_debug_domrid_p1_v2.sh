#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_dbg_${TS}" && echo "[BACKUP] $F.bak_kpi_dbg_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

m1="VSP_KPI_STANDALONE_FROM_FINDINGS_V2_P1_V1"
if m1 not in s:
    raise SystemExit("[ERR] standalone marker not found; run append patch first")

m2="VSP_KPI_STANDALONE_DEBUG_DOMRID_P1_V2"
if m2 in s:
    print("[SKIP] marker exists:", m2)
    raise SystemExit(0)

# 1) Add DOM text fallback inside ridFromState() just before "return \"\";"
# (best-effort: only patch first occurrence after marker)
idx=s.find(m1)
seg=s[idx:idx+12000]

pat_return = re.compile(r'(function\s+ridFromState\s*\(\)\s*\{[\s\S]*?)(\n\s*return\s+"";\s*\n\s*\})', re.M)
m=pat_return.search(seg)
if not m:
    raise SystemExit("[ERR] cannot find ridFromState() block near standalone marker")

dom_fallback = r'''
    try{
      // fallback: read RID from page text (header shows "RID: VSP_CI_...")
      var txt = (document && document.body && (document.body.innerText||"")) ? document.body.innerText : "";
      var mm = txt.match(/RID:\s*(VSP_CI_\d{8}_\d{6})/i);
      if(mm && mm[1]) return normRid(mm[1]);
    }catch(_){}
'''
seg2 = seg[:m.start(2)] + dom_fallback + seg[m.start(2):]

# 2) After setText() function, write BOOT marker once (visible)
pat_settext_end = re.compile(r'(function\s+setText\s*\([\s\S]*?\n\s*\}\s*\n)', re.M)
m=pat_settext_end.search(seg2)
if not m:
    raise SystemExit("[ERR] cannot find setText() in standalone block")

boot = r'''
  // === VSP_KPI_STANDALONE_DEBUG_DOMRID_P1_V2 ===
  try{
    setText("kpi-overall", "BOOT");
    setText("kpi-overall-sub", "standalone alive (boot)");
  }catch(_){}
'''
seg3 = seg2[:m.end()] + boot + seg2[m.end():]

# 3) Inside tick(), update sub text each tick so you can SEE it running
pat_tick = re.compile(r'(async\s+function\s+tick\s*\(\)\s*\{\s*)([\s\S]*?)(\n\s*\}\s*\n)', re.M)
m=pat_tick.search(seg3)
if not m:
    raise SystemExit("[ERR] cannot find tick() in standalone block")

tick_ins = r'''
    try{
      var now = new Date();
      setText("kpi-overall-sub", "tick " + now.toISOString());
    }catch(_){}
'''
seg4 = seg3[:m.start(2)] + tick_ins + seg3[m.start(2):]

# write back whole file
s2 = s[:idx] + seg4 + s[idx+len(seg):]
# tag marker once
s2 += "\n// " + m2 + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] patched", m2)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
