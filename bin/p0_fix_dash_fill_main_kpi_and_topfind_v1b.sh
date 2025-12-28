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
cp -f "$JS" "${JS}.bak_fix_fill_main_v1b_${TS}"
echo "[BACKUP] ${JS}.bak_fix_fill_main_v1b_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

START="/* ===================== VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1"
END="/* ===================== /VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1"

fixed = r"""/* ===================== VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1 =====================
   Goal: Populate main KPI cards + main Top Findings table by hooking MIN_STABLE overlay buttons.
   Safe: no loops, no bind storms.
*/
(()=> {
  try{
    if (window.__VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1) return;
    window.__VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1 = true;

    const log=(...a)=>console.log("[VSP][FILL_MAIN_V1]",...a);

    function esc(s){
      return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    }

    function u(s){ return String(s||"").trim().toUpperCase(); }
    function l(s){ return String(s||"").trim().toLowerCase(); }

    // ---- KPI fill by label text (TOTAL/CRITICAL/HIGH/MEDIUM/LOW/INFO/TRACE) ----
    function findLabelEl(label){
      const want = u(label);
      const all = document.querySelectorAll("div,span,small,strong,b,h1,h2,h3,h4");
      for (const el of all){
        const t = u(el.textContent || "");
        if (t === want) return el;
      }
      return null;
    }

    function fillOneKpi(label, value){
      const labEl = findLabelEl(label);
      if (!labEl) return false;

      // climb to a reasonable card container
      let root = labEl;
      for (let i=0; i<8 && root && root.parentElement; i++){
        root = root.parentElement;
        const txt = u(root.textContent||"");
        // heuristic: container includes label and at least one dash
        if (txt.indexOf(u(label)) >= 0 && (root.textContent||"").indexOf("—") >= 0) break;
      }
      if (!root) return false;

      // replace first dash-like element inside the container
      const els = root.querySelectorAll("div,span,strong,b");
      for (const el of els){
        const t = (el.textContent||"").trim();
        if (t === "—" || t === "-" || t === "--"){
          el.textContent = String(value ?? "-");
          return true;
        }
      }
      return false;
    }

    function fillKpisFromSummary(summary){
      const c = (summary && summary.counts_total) ? summary.counts_total : {};
      const total = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].reduce((a,k)=>a+(Number(c[k]||0)||0),0);
      fillOneKpi("TOTAL", total);
      fillOneKpi("CRITICAL", c.CRITICAL);
      fillOneKpi("HIGH", c.HIGH);
      fillOneKpi("MEDIUM", c.MEDIUM);
      fillOneKpi("LOW", c.LOW);
      fillOneKpi("INFO", c.INFO);
      fillOneKpi("TRACE", c.TRACE);
      log("kpi filled", {total});
    }

    // ---- Top findings main table: pick table that has headers Severity/Tool/Title/Location ----
    function findMainTopTableTbody(){
      const tables = Array.from(document.querySelectorAll("table"));
      for (const t of tables){
        const h = l(t.innerText || "");
        if (h.includes("severity") && h.includes("tool") && h.includes("title") && (h.includes("location") || h.includes("loc"))){
          const tb = t.querySelector("tbody");
          if (tb) return tb;
        }
      }
      return null;
    }

    function renderTopFindingsInMain(items){
      const tbody = findMainTopTableTbody();
      if (!tbody){
        log("cannot find main Top findings table");
        return false;
      }
      if (!Array.isArray(items) || items.length === 0){
        tbody.innerHTML = '<tr><td colspan="4" style="padding:10px;opacity:.75">No items</td></tr>';
        return true;
      }
      tbody.innerHTML = items.map(it=>{
        const sev = esc(it.severity||"");
        const tool = esc(it.tool||"");
        const title = esc(it.title||"");
        const loc = esc((it.file||"") + (it.line ? (":" + it.line) : ""));
        return `<tr>
          <td style="padding:10px;border-top:1px solid rgba(255,255,255,.06)">${sev}</td>
          <td style="padding:10px;border-top:1px solid rgba(255,255,255,.06)">${tool}</td>
          <td style="padding:10px;border-top:1px solid rgba(255,255,255,.06)">${title}</td>
          <td style="padding:10px;border-top:1px solid rgba(255,255,255,.06);font-family:ui-monospace,Menlo,Consolas,monospace">${loc}</td>
        </tr>`;
      }).join("");
      return true;
    }

    // ---- Hook MIN_STABLE overlay buttons ----
    async function getRidFromPanel(){
      const ridEl = document.getElementById("vsp_ms_rid");
      const rid = ridEl ? (ridEl.textContent||"").trim() : "";
      return rid || "";
    }

    function hookOnce(){
      const btnReload = document.getElementById("vsp_ms_reload");
      const btnTop = document.getElementById("vsp_ms_top");

      if (btnReload && !btnReload.__vsp_fill_main_hooked){
        btnReload.__vsp_fill_main_hooked = true;
        btnReload.addEventListener("click", async ()=>{
          try{
            const rid = await getRidFromPanel();
            if (!rid) return;
            const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`;
            const res = await fetch(url, {cache:"no-store"});
            const j = await res.json();
            fillKpisFromSummary(j);
          }catch(e){ console.error("[VSP][FILL_MAIN_V1] reload hook err", e); }
        });
      }

      if (btnTop && !btnTop.__vsp_fill_main_hooked){
        btnTop.__vsp_fill_main_hooked = true;
        btnTop.addEventListener("click", async ()=>{
          try{
            const rid = await getRidFromPanel();
            if (!rid) return;
            const url = `/api/vsp/top_findings_v4?rid=${encodeURIComponent(rid)}&limit=25`;
            const res = await fetch(url, {cache:"no-store"});
            const j = await res.json();
            if (j && j.ok) renderTopFindingsInMain(j.items||[]);
            else log("top findings not ok", j);
          }catch(e){ console.error("[VSP][FILL_MAIN_V1] top hook err", e); }
        });
      }

      log("hooked MIN_STABLE buttons -> main fill");
    }

    // try a few times (very light) to wait overlay creation
    let tries = 0;
    const iv = setInterval(()=>{
      tries++;
      hookOnce();
      if (document.getElementById("vsp_ms_top") || tries >= 10) clearInterval(iv);
    }, 200);

  }catch(e){
    console.error("[VSP][FILL_MAIN_V1] fatal", e);
  }
})();
/* ===================== /VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1 ===================== */
"""

i = s.find(START)
j = s.find(END)

if i != -1 and j != -1 and j > i:
    # replace old broken block
    j_end = s.find("*/", j)
    if j_end != -1:
        j_end = j_end + 2
    else:
        j_end = j + len(END)
    s2 = s[:i] + fixed + s[j_end:]
    p.write_text(s2, encoding="utf-8")
    print("[OK] replaced broken block with fixed JS")
else:
    p.write_text(s + "\n\n" + fixed + "\n", encoding="utf-8")
    print("[OK] appended fixed JS (old block not found)")
PY

node --check "$JS"
echo "[OK] node --check passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Ctrl+Shift+R /vsp5 -> bấm Reload summary + Load top findings (25) để fill KPI + table ở layout chính."
