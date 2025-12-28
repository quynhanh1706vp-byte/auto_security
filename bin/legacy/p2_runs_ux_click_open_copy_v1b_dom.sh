#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

JS="static/js/vsp_runs_kpi_compact_v3.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_runsux_dom_${TS}"
echo "[BACKUP] ${JS}.bak_runsux_dom_${TS}"

python3 - "$JS" <<'PY'
import sys, textwrap
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_RUNS_UX_CLICK_OPEN_COPY_V1B_DOM"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* VSP_P2_RUNS_UX_CLICK_OPEN_COPY_V1B_DOM */
(function(){
  function isRuns(){ return String(location.pathname||"").includes("/runs"); }
  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }

  function ensureActionsHeader(table){
    const thead = table.querySelector("thead");
    if(!thead) return;
    const tr = thead.querySelector("tr");
    if(!tr) return;
    const ths = tr.querySelectorAll("th");
    // If already has Actions, skip
    for(const th of ths){ if((th.textContent||"").trim().toLowerCase()==="actions") return; }
    const th=document.createElement("th");
    th.textContent="Actions";
    th.style.cssText="padding:10px 12px;border-bottom:1px solid rgba(255,255,255,0.10)";
    tr.appendChild(th);
  }

  function addCopyButtons(table){
    const rows=qsa("tbody tr[data-rid]", table);
    for(const tr of rows){
      if(tr.getAttribute("data-runs-ux") === "1") continue;
      tr.setAttribute("data-runs-ux","1");

      // Add actions cell if not present
      const tds=tr.querySelectorAll("td");
      // If already has 4th td containing a button, skip adding
      if(tds.length < 4){
        const td=document.createElement("td");
        td.style.cssText="padding:10px 12px;white-space:nowrap";
        const btn=document.createElement("button");
        btn.setAttribute("data-testid","runs-copy-rid");
        btn.textContent="Copy";
        btn.style.cssText="padding:7px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit;cursor:pointer;font-size:12px";
        btn.onmouseenter=()=>btn.style.background="rgba(255,255,255,0.06)";
        btn.onmouseleave=()=>btn.style.background="rgba(255,255,255,0.04)";
        btn.onclick=(e)=>{
          e.preventDefault(); e.stopPropagation();
          const rid=tr.getAttribute("data-rid")||"";
          if(rid) navigator.clipboard?.writeText(rid).catch(()=>{});
        };
        td.appendChild(btn);
        tr.appendChild(td);
      }

      // Row click => open drawer (dispatch dblclick to trigger existing drawer hook)
      tr.style.cursor="pointer";
      tr.onclick=(e)=>{
        // If user clicked the copy button, it already stopped propagation
        // Open drawer by simulating dblclick (your drawer hook listens to dblclick)
        try{
          tr.dispatchEvent(new MouseEvent("dblclick", {bubbles:true, cancelable:true, view:window}));
        }catch(_){}
      };
    }
  }

  function applyOnce(){
    const host=qs('[data-testid="runs-table-host"]');
    if(!host) return;
    const table=host.querySelector("table");
    if(!table) return;
    ensureActionsHeader(table);
    addCopyButtons(table);
  }

  function boot(){
    if(!isRuns()) return;
    applyOnce();
    const obs=new MutationObserver(()=>applyOnce());
    obs.observe(document.body, {subtree:true, childList:true});
  }

  if(isRuns()){
    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  }
})();
""")

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended DOM UX patch")
PY

node -c "$JS"
echo "[OK] node -c OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

echo "== verify marker in served JS =="
curl -fsS "$BASE/static/js/$(basename "$JS")" | grep -n "VSP_P2_RUNS_UX_CLICK_OPEN_COPY_V1B_DOM" | head -n 2
