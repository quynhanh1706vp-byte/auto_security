#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

# idempotent
grep -q "VSP_EXPORT_BUTTONS_V1" "$T" && { echo "[OK] export buttons already present"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_exportbtn_${TS}"
echo "[BACKUP] $T.bak_exportbtn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("templates/vsp_4tabs_commercial_v1.html")
s = p.read_text(encoding="utf-8", errors="replace")

btn = r"""
<!-- VSP_EXPORT_BUTTONS_V1 BEGIN -->
<div class="vsp-card" style="margin-top:12px">
  <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap">
    <button class="vsp-btn" id="btn-export-html">Export HTML</button>
    <button class="vsp-btn" id="btn-export-zip">Export ZIP</button>
    <button class="vsp-btn" id="btn-export-pdf">Export PDF</button>
    <span style="opacity:.75;font-size:12px">RID: <span id="export-rid">(auto)</span></span>
  </div>
</div>
<script>
(function(){
  function pickRid(){
    // try: current selected in runs tab; else dashboard_v3 run_id; else first item of runs index
    const el = document.querySelector("[data-vsp-selected-run-id]");
    if (el && el.getAttribute("data-vsp-selected-run-id")) return el.getAttribute("data-vsp-selected-run-id");
    return null;
  }
  async function ensureRid(){
    let rid = pickRid();
    if (!rid){
      try{
        const d = await fetch("/api/vsp/dashboard_v3");
        if (d.ok){
          const j = await d.json();
          if (j && j.run_id) rid = j.run_id;
        }
      }catch(e){}
    }
    if (!rid){
      try{
        const r = await fetch("/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1");
        if (r.ok){
          const j = await r.json();
          rid = (j.items && j.items[0] && j.items[0].run_id) ? j.items[0].run_id : null;
        }
      }catch(e){}
    }
    document.getElementById("export-rid").textContent = rid || "(none)";
    return rid;
  }
  async function go(fmt){
    const rid = await ensureRid();
    if (!rid){ alert("No run_id available"); return; }
    const url = `/api/vsp/run_export_v3/${encodeURIComponent(rid)}?fmt=${fmt}`;
    window.open(url, "_blank");
  }
  document.getElementById("btn-export-html").addEventListener("click", ()=>go("html"));
  document.getElementById("btn-export-zip").addEventListener("click", ()=>go("zip"));
  document.getElementById("btn-export-pdf").addEventListener("click", ()=>go("pdf"));
  ensureRid();
})();
</script>
<!-- VSP_EXPORT_BUTTONS_V1 END -->
"""

# Insert near top of body after first main container marker (best-effort)
m = re.search(r'(<body[^>]*>)', s, re.I)
if not m:
    raise SystemExit("no <body> found")

# put right after body tag for visibility
idx = m.end()
s2 = s[:idx] + "\n" + btn + "\n" + s[idx:]

p.write_text(s2, encoding="utf-8")
print("[OK] inserted export buttons block")
PY
echo "[DONE] patched $T"
