#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_wire_main_v1d_${TS}"
echo "[BACKUP] ${JS}.bak_wire_main_v1d_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_DASH_WIRE_MAIN_TOPFIND_V1D"
if MARK in s:
    print("[SKIP] already appended:", MARK)
else:
    s += "\n\n" + textwrap.dedent(r"""
/* ===================== VSP_P0_DASH_WIRE_MAIN_TOPFIND_V1D =====================
   Hard-wire "Load top findings" button -> render into MAIN Top findings table
   by matching table header text (Severity/Tool/Title/Location).
*/
(()=> {
  try{
    if (window.__VSP_P0_DASH_WIRE_MAIN_TOPFIND_V1D) return;
    window.__VSP_P0_DASH_WIRE_MAIN_TOPFIND_V1D = true;

    const log=(...a)=>console.log("[VSP][WIRE_TOPFIND_V1D]",...a);
    const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

    function findMainTopTable(){
      const tables = Array.from(document.querySelectorAll("table"));
      for (const t of tables){
        const txt = (t.textContent||"").toLowerCase();
        if (txt.includes("severity") && txt.includes("tool") && txt.includes("title") && (txt.includes("location") || txt.includes("loc"))){
          return t;
        }
      }
      // fallback: table inside section containing "Top findings"
      const nodes = Array.from(document.querySelectorAll("h1,h2,h3,h4,div,span,strong,b"));
      for (const n of nodes){
        const tt=(n.textContent||"").toLowerCase();
        if (tt.includes("top findings")){
          let root=n;
          for (let i=0;i<12 && root && root.parentElement;i++){
            root=root.parentElement;
            const t=root.querySelector && root.querySelector("table");
            if (t) return t;
          }
        }
      }
      return null;
    }

    function getTbody(table){
      if (!table) return null;
      let tb = table.querySelector("tbody");
      if (!tb){
        tb = document.createElement("tbody");
        table.appendChild(tb);
      }
      return tb;
    }

    function renderMain(items){
      const table = findMainTopTable();
      const tbody = getTbody(table);
      if (!tbody){
        log("no main top table found");
        return false;
      }
      if (!Array.isArray(items) || items.length===0){
        tbody.innerHTML = '<tr><td colspan="4" style="padding:10px;opacity:.75">No items</td></tr>';
        return true;
      }
      tbody.innerHTML = items.map(it=>{
        const sev=esc(it.severity||"");
        const tool=esc(it.tool||"");
        const title=esc(it.title||"");
        const loc=esc((it.file||"") + (it.line?(":"+it.line):""));
        return `<tr>
          <td style="padding:10px;border-top:1px solid rgba(255,255,255,.06)">${sev}</td>
          <td style="padding:10px;border-top:1px solid rgba(255,255,255,.06)">${tool}</td>
          <td style="padding:10px;border-top:1px solid rgba(255,255,255,.06)">${title}</td>
          <td style="padding:10px;border-top:1px solid rgba(255,255,255,.06);font-family:ui-monospace,Menlo,Consolas,monospace">${loc}</td>
        </tr>`;
      }).join("");
      return true;
    }

    async function getRid(){
      const ridEl = document.getElementById("vsp_ms_rid");
      const rid = ridEl ? (ridEl.textContent||"").trim() : "";
      if (rid) return rid;
      const res = await fetch("/api/vsp/rid_latest_gate_root", {cache:"no-store"});
      const j = await res.json();
      return j && j.rid ? String(j.rid) : "";
    }

    async function loadAndRender(limit=25){
      const rid = await getRid();
      if (!rid){ log("no rid"); return; }
      const url = `/api/vsp/top_findings_v4?rid=${encodeURIComponent(rid)}&limit=${encodeURIComponent(limit)}`;
      log("fetch", url);
      const res = await fetch(url, {cache:"no-store"});
      const j = await res.json();
      if (j && j.ok){
        renderMain(j.items||[]);
        log("render ok", {n:(j.items||[]).length, rid, source:j.source});
      }else{
        log("render not ok", j);
      }
    }

    function bindButtons(){
      const btns = Array.from(document.querySelectorAll("button,[role='button']"));
      let bound=0;
      for (const b of btns){
        const t=(b.textContent||"").toLowerCase().trim();
        if (!t.includes("load top findings")) continue;
        if (b.__vsp_wire_v1d) continue;
        b.__vsp_wire_v1d = true;
        b.addEventListener("click", (e)=>{ e.preventDefault(); loadAndRender(25); });
        bound++;
      }
      log("bound buttons", bound);
    }

    // bind once after DOM ready (no loops)
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", bindButtons, {once:true});
    } else {
      bindButtons();
    }

  }catch(e){
    console.error("[VSP][WIRE_TOPFIND_V1D] fatal", e);
  }
})();
/* ===================== /VSP_P0_DASH_WIRE_MAIN_TOPFIND_V1D ===================== */
""") + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

node --check "$JS"
echo "[OK] node --check passed"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Ctrl+Shift+R /vsp5 -> bấm 'Load top findings (25)' (ở layout chính) => bảng main sẽ đổ dữ liệu semgrep."
