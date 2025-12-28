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
cp -f "$JS" "${JS}.bak_topfind_inject_v1e_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_inject_v1e_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_TOPFIND_INJECT_MAIN_PANEL_V1E"
if MARK in s:
    print("[SKIP] already appended:", MARK)
else:
    s += "\n\n" + textwrap.dedent(r"""
/* ===================== VSP_P0_TOPFIND_INJECT_MAIN_PANEL_V1E =====================
   Guarantee Top findings renders in MAIN panel by injecting our own table into
   the "Top findings" section (no dependency on existing DOM/table structure).
*/
(()=> {
  try{
    if (window.__VSP_P0_TOPFIND_INJECT_MAIN_PANEL_V1E) return;
    window.__VSP_P0_TOPFIND_INJECT_MAIN_PANEL_V1E = true;

    const log=(...a)=>console.log("[VSP][TOPFIND_INJECT_V1E]",...a);
    const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

    function findTopFindingsSection(){
      const needles=["top findings (sample)","top findings"];
      const els = Array.from(document.querySelectorAll("h1,h2,h3,h4,div,span,strong,b,p"));
      for (const el of els){
        const t=(el.textContent||"").toLowerCase().trim();
        if (!t) continue;
        if (!needles.some(n=>t.includes(n))) continue;
        // climb to a container that likely is the section card
        let cur=el;
        for (let i=0;i<10 && cur && cur.parentElement;i++){
          cur=cur.parentElement;
          // heuristic: section should contain the headings "Severity Tool Title"
          const tx=(cur.textContent||"").toLowerCase();
          if (tx.includes("severity") && tx.includes("tool") && tx.includes("title")) return cur;
        }
      }
      return null;
    }

    function ensureInjectedUI(){
      const sec = findTopFindingsSection();
      if (!sec){ log("no section found"); return null; }

      let box = sec.querySelector("#vsp_topfind_live_box_v1e");
      if (box) return box;

      box = document.createElement("div");
      box.id = "vsp_topfind_live_box_v1e";
      box.style.marginTop = "10px";
      box.style.padding = "10px";
      box.style.border = "1px solid rgba(255,255,255,.08)";
      box.style.borderRadius = "12px";
      box.style.background = "rgba(10,14,26,.35)";

      box.innerHTML = `
        <div style="display:flex;align-items:center;gap:10px;justify-content:space-between;">
          <div style="font-weight:600">Top findings (live)</div>
          <div id="vsp_topfind_live_status_v1e" style="opacity:.75;font-size:12px">Idle</div>
        </div>
        <div style="overflow:auto;margin-top:8px">
          <table style="width:100%;border-collapse:collapse;font-size:12px">
            <thead>
              <tr style="opacity:.85">
                <th style="text-align:left;padding:8px;border-bottom:1px solid rgba(255,255,255,.08)">Severity</th>
                <th style="text-align:left;padding:8px;border-bottom:1px solid rgba(255,255,255,.08)">Tool</th>
                <th style="text-align:left;padding:8px;border-bottom:1px solid rgba(255,255,255,.08)">Title</th>
                <th style="text-align:left;padding:8px;border-bottom:1px solid rgba(255,255,255,.08)">Location</th>
              </tr>
            </thead>
            <tbody id="vsp_topfind_live_tbody_v1e">
              <tr><td colspan="4" style="padding:10px;opacity:.75">Not loaded</td></tr>
            </tbody>
          </table>
        </div>
      `;

      // insert near bottom of section
      sec.appendChild(box);
      log("injected live box ok");
      return box;
    }

    function setStatus(msg){
      const el=document.getElementById("vsp_topfind_live_status_v1e");
      if (el) el.textContent = msg;
    }

    function render(items){
      const tb=document.getElementById("vsp_topfind_live_tbody_v1e");
      if (!tb) return;
      if (!Array.isArray(items) || items.length===0){
        tb.innerHTML = '<tr><td colspan="4" style="padding:10px;opacity:.75">No items</td></tr>';
        return;
      }
      tb.innerHTML = items.map(it=>{
        const sev=esc(it.severity||"");
        const tool=esc(it.tool||"");
        const title=esc(it.title||"");
        const loc=esc((it.file||"") + (it.line?(":"+it.line):""));
        return `<tr>
          <td style="padding:8px;border-top:1px solid rgba(255,255,255,.06)">${sev}</td>
          <td style="padding:8px;border-top:1px solid rgba(255,255,255,.06)">${tool}</td>
          <td style="padding:8px;border-top:1px solid rgba(255,255,255,.06)">${title}</td>
          <td style="padding:8px;border-top:1px solid rgba(255,255,255,.06);font-family:ui-monospace,Menlo,Consolas,monospace">${loc}</td>
        </tr>`;
      }).join("");
    }

    async function getRid(){
      // try MIN_STABLE label first if exists
      const ridEl = document.getElementById("vsp_ms_rid");
      const rid = ridEl ? (ridEl.textContent||"").trim() : "";
      if (rid) return rid;
      const res = await fetch("/api/vsp/rid_latest_gate_root", {cache:"no-store"});
      const j = await res.json();
      return j && j.rid ? String(j.rid) : "";
    }

    async function load(limit=25){
      ensureInjectedUI();
      setStatus("Loading…");
      const rid = await getRid();
      if (!rid){ setStatus("No RID"); return; }
      const url = `/api/vsp/top_findings_v4?rid=${encodeURIComponent(rid)}&limit=${encodeURIComponent(limit)}`;
      log("fetch", url);
      const res = await fetch(url, {cache:"no-store"});
      const j = await res.json();
      if (!j || !j.ok){
        setStatus(`No data (${(j&&j.err)||"err"})`);
        log("no data", j);
        render([]);
        return;
      }
      render(Array.isArray(j.items)?j.items:[]);
      setStatus(`Loaded ${(j.items||[]).length} • ${j.source||"v4"} • ${rid}`);
      log("render ok", {n:(j.items||[]).length, rid, source:j.source});
    }

    function bind(){
      // bind all "Load top findings" buttons
      const btns = Array.from(document.querySelectorAll("button,[role='button']"));
      let bound=0;
      for (const b of btns){
        const t=(b.textContent||"").toLowerCase().trim();
        if (!t.includes("load top findings")) continue;
        if (b.__vsp_inject_v1e) continue;
        b.__vsp_inject_v1e = true;
        b.addEventListener("click", (e)=>{ e.preventDefault(); load(25); }, {capture:true});
        bound++;
      }
      log("bound buttons", bound);
    }

    function boot(){
      ensureInjectedUI();
      bind();
      // do NOT auto-load (commercial safe). user click triggers load.
      log("boot ok");
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, {once:true});
    else boot();

  }catch(e){
    console.error("[VSP][TOPFIND_INJECT_V1E] fatal", e);
  }
})();
/* ===================== /VSP_P0_TOPFIND_INJECT_MAIN_PANEL_V1E ===================== */
""") + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

node --check "$JS"
echo "[OK] node --check passed"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Ctrl+Shift+R /vsp5 -> bấm 'Load top findings (25)' => sẽ hiện 'Top findings (live)' ngay trong panel main."
