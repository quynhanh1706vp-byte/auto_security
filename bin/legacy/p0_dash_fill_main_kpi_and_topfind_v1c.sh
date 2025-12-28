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
cp -f "$JS" "${JS}.bak_fill_main_v1c_${TS}"
echo "[BACKUP] ${JS}.bak_fill_main_v1c_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1C"
if MARK in s:
    print("[SKIP] already appended:", MARK)
else:
    s += "\n\n" + textwrap.dedent(r"""
/* ===================== VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1C =====================
   Robust fill for main KPI cards + Top findings table by label proximity.
   - No loops/bind storms
   - Hooks MIN_STABLE buttons if present
*/
(()=> {
  try{
    if (window.__VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1C) return;
    window.__VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1C = true;

    const log=(...a)=>console.log("[VSP][FILL_MAIN_V1C]",...a);
    const LABELS=["TOTAL","CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];

    const U=s=>String(s||"").trim().toUpperCase();
    const L=s=>String(s||"").trim().toLowerCase();

    function esc(s){
      return String(s ?? "").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    }

    function isDashLike(t){
      t = String(t||"").trim();
      return t==="" || t==="—" || t==="-" || t==="--";
    }

    function numLike(t){
      const x = String(t||"").trim();
      if (!x) return false;
      return /^[0-9]{1,9}$/.test(x);
    }

    // Find the element that displays the label (exact match)
    function findLabelEl(label){
      const want = U(label);
      // Prefer small texts (labels are short)
      const cands = document.querySelectorAll("div,span,small,strong,b");
      for (const el of cands){
        const t = U(el.textContent||"");
        if (t === want) return el;
      }
      return null;
    }

    // Given label element, pick best nearby "value" element to set.
    function pickValueElFromLabel(labelEl){
      if (!labelEl) return null;

      // 1) sibling candidates
      const sibs = [];
      if (labelEl.parentElement){
        for (const ch of Array.from(labelEl.parentElement.children)){
          if (ch === labelEl) continue;
          sibs.push(ch);
        }
      }

      // 2) within parent: any element that looks like a value
      const parent = labelEl.parentElement || labelEl;
      const within = Array.from(parent.querySelectorAll("div,span,strong,b")).filter(x => x !== labelEl);

      const pool = [...sibs, ...within].filter(Boolean);

      // Prefer dash/empty or numeric placeholders, and prefer "bigger" font-size.
      let best = null;
      let bestScore = -1;

      for (const el of pool){
        const t = (el.textContent||"").trim();
        if (U(t) === U(labelEl.textContent||"")) continue;
        // ignore if it contains too much text (likely container)
        if (t.length > 20 && !numLike(t) && !isDashLike(t)) continue;

        let score = 0;
        if (isDashLike(t)) score += 3;
        if (numLike(t)) score += 2;

        // font size heuristic
        try{
          const fs = parseFloat(getComputedStyle(el).fontSize || "0") || 0;
          score += Math.min(3, fs / 10);
        }catch(e){}

        // nearer sibling bonus
        if (el.parentElement === parent) score += 1;

        if (score > bestScore){
          bestScore = score;
          best = el;
        }
      }

      // 3) fallback: previous sibling chain
      if (!best && labelEl.previousElementSibling) best = labelEl.previousElementSibling;

      return best;
    }

    function fillOne(label, value){
      const lab = findLabelEl(label);
      if (!lab) return false;
      const valEl = pickValueElFromLabel(lab);
      if (!valEl) return false;
      valEl.textContent = String(value ?? "-");
      return true;
    }

    function fillKpisFromSummary(summary){
      const c = (summary && summary.counts_total) ? summary.counts_total : {};
      const total = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].reduce((a,k)=>a+(Number(c[k]||0)||0),0);

      const map = {
        TOTAL: total,
        CRITICAL: c.CRITICAL ?? 0,
        HIGH: c.HIGH ?? 0,
        MEDIUM: c.MEDIUM ?? 0,
        LOW: c.LOW ?? 0,
        INFO: c.INFO ?? 0,
        TRACE: c.TRACE ?? 0,
      };

      let ok=0;
      for (const k of LABELS){
        if (fillOne(k, map[k])) ok++;
      }
      log("kpi filled", {ok, rid: summary && summary.rid, overall: summary && summary.overall});
      return ok;
    }

    // --- Top findings main section/table ---
    function findTopSection(){
      const els = document.querySelectorAll("h1,h2,h3,h4,div,span,strong,b");
      for (const el of els){
        const t = L(el.textContent||"");
        if (t.includes("top findings")){
          // climb to a section-like container
          let root = el;
          for (let i=0;i<10 && root && root.parentElement;i++){
            root = root.parentElement;
            if (root.querySelector && root.querySelector("table")) return root;
          }
          return el.parentElement || el;
        }
      }
      return null;
    }

    function getTopTableBody(){
      const sec = findTopSection();
      if (!sec) return null;
      let table = sec.querySelector("table");
      if (!table){
        // create table minimal (rare)
        table = document.createElement("table");
        table.style.width="100%";
        sec.appendChild(table);
      }
      let tbody = table.querySelector("tbody");
      if (!tbody){
        tbody = document.createElement("tbody");
        table.appendChild(tbody);
      }
      return tbody;
    }

    function renderTop(items){
      const tbody = getTopTableBody();
      if (!tbody){
        log("cannot find top table");
        return false;
      }
      if (!Array.isArray(items) || items.length===0){
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

    async function getRidFromPanelOrApi(){
      const ridEl = document.getElementById("vsp_ms_rid");
      const rid = ridEl ? (ridEl.textContent||"").trim() : "";
      if (rid) return rid;
      const res = await fetch("/api/vsp/rid_latest_gate_root", {cache:"no-store"});
      const j = await res.json();
      return (j && j.rid) ? String(j.rid) : "";
    }

    async function loadSummaryAndFill(){
      const rid = await getRidFromPanelOrApi();
      if (!rid) return;
      const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`;
      const res = await fetch(url, {cache:"no-store"});
      const j = await res.json();
      j.rid = rid;
      fillKpisFromSummary(j);
    }

    async function loadTopAndRender(){
      const rid = await getRidFromPanelOrApi();
      if (!rid) return;
      const url = `/api/vsp/top_findings_v4?rid=${encodeURIComponent(rid)}&limit=25`;
      const res = await fetch(url, {cache:"no-store"});
      const j = await res.json();
      if (j && j.ok){
        renderTop(j.items||[]);
        log("top rendered", {n:(j.items||[]).length, rid, source:j.source});
      }else{
        log("top not ok", j);
      }
    }

    // Hook MIN_STABLE buttons if exist
    function hook(){
      const btnReload = document.getElementById("vsp_ms_reload");
      const btnTop = document.getElementById("vsp_ms_top");

      if (btnReload && !btnReload.__vsp_fill_v1c){
        btnReload.__vsp_fill_v1c = true;
        btnReload.addEventListener("click", ()=>{ loadSummaryAndFill(); });
      }
      if (btnTop && !btnTop.__vsp_fill_v1c){
        btnTop.__vsp_fill_v1c = true;
        btnTop.addEventListener("click", ()=>{ loadTopAndRender(); });
      }
      if (btnReload || btnTop) log("hooked MIN_STABLE buttons");
    }

    // Light bootstrap (no loops): try hook a few times only
    let tries=0;
    const iv=setInterval(()=>{
      tries++;
      hook();
      if (document.getElementById("vsp_ms_reload") || tries>=10) clearInterval(iv);
    }, 200);

    // Auto-fill KPI once after load (safe, tiny JSON)
    setTimeout(()=>{ loadSummaryAndFill(); }, 600);

  }catch(e){
    console.error("[VSP][FILL_MAIN_V1C] fatal", e);
  }
})();
/* ===================== /VSP_P0_DASH_FILL_MAIN_KPI_TOPFIND_V1C ===================== */
""") + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

node --check "$JS"
echo "[OK] node --check passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Ctrl+Shift+R /vsp5 -> KPI main sẽ tự fill sau ~1s; bấm 'Load top findings (25)' trên MIN_STABLE để đổ bảng main."
