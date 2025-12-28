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
cp -f "$JS" "${JS}.bak_topfind_panel_v2_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_panel_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap
p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_TOPFIND_UI_CAPTURE_PANEL_V2"
if MARK in s:
    print("[SKIP] already patched")
else:
    block=textwrap.dedent(r"""
    /* ===================== VSP_P0_TOPFIND_UI_CAPTURE_PANEL_V2 ===================== */
    (()=> {
      try{
        if (window.__vsp_topfind_ui_panel_v2) return;
        window.__vsp_topfind_ui_panel_v2 = true;

        const log=(...a)=>console.log("[VSP][TOPFIND_PANEL_V2]",...a);
        const norm=(x)=>String(x||"").toLowerCase().replace(/\s+/g," ").trim();

        function findTopFindContainer(){
          // Locate a block that contains the "Top findings" title
          const all = Array.from(document.querySelectorAll("h1,h2,h3,h4,div,span,strong,b"));
          for (const el of all){
            const t = norm(el.textContent);
            if (t.startsWith("top findings")){
              return el.closest("section,div") || el.parentElement || document.body;
            }
          }
          return document.body;
        }

        function ensurePanel(){
          let p = document.getElementById("vsp_topfind_panel_v2");
          if (p) return p;
          const host = findTopFindContainer();
          p = document.createElement("div");
          p.id="vsp_topfind_panel_v2";
          p.style.marginTop="10px";
          p.style.padding="10px";
          p.style.border="1px solid rgba(255,255,255,0.08)";
          p.style.borderRadius="10px";
          p.style.background="rgba(255,255,255,0.03)";
          p.innerHTML = `
            <div style="display:flex;gap:10px;align-items:center;justify-content:space-between;">
              <div style="font-weight:600;opacity:.9">Top findings (live)</div>
              <div id="vsp_topfind_status_v2" style="font-size:12px;opacity:.75">Ready</div>
            </div>
            <div style="overflow:auto;margin-top:8px;">
              <table style="width:100%;border-collapse:collapse;font-size:13px">
                <thead>
                  <tr style="opacity:.75;text-align:left">
                    <th style="padding:6px 8px;white-space:nowrap">Severity</th>
                    <th style="padding:6px 8px;white-space:nowrap">Tool</th>
                    <th style="padding:6px 8px;">Title</th>
                    <th style="padding:6px 8px;white-space:nowrap">Location</th>
                  </tr>
                </thead>
                <tbody id="vsp_topfind_tbody_v2">
                  <tr><td colspan="4" style="padding:8px;opacity:.7">Not loaded</td></tr>
                </tbody>
              </table>
            </div>
          `;
          host.appendChild(p);
          return p;
        }

        function setStatus(msg){
          ensurePanel();
          const el=document.getElementById("vsp_topfind_status_v2");
          if (el) el.textContent=msg;
        }

        async function getLatestRid(){
          const r = await fetch("/api/vsp/rid_latest_gate_root", {cache:"no-store"});
          const j = await r.json();
          return (j && j.rid) ? j.rid : "";
        }

        function esc(s){ return String(s||"").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;" }[c])); }

        function render(items){
          ensurePanel();
          const tb=document.getElementById("vsp_topfind_tbody_v2");
          if (!tb) return;
          if (!items.length){
            tb.innerHTML = `<tr><td colspan="4" style="padding:8px;opacity:.7">No findings</td></tr>`;
            return;
          }
          tb.innerHTML = items.map(it=>{
            const sev=esc(it.severity||"INFO");
            const tool=esc(it.tool||"");
            const title=esc(it.title||"");
            const loc=esc(((it.file||"") + (it.line? (":"+it.line):"")).trim());
            return `<tr style="border-top:1px solid rgba(255,255,255,0.06)">
              <td style="padding:6px 8px;white-space:nowrap">${sev}</td>
              <td style="padding:6px 8px;white-space:nowrap">${tool}</td>
              <td style="padding:6px 8px">${title}</td>
              <td style="padding:6px 8px;white-space:nowrap">${loc}</td>
            </tr>`;
          }).join("");
        }

        async function load(limit=25){
          setStatus("Loading…");
          const rid = await getLatestRid();
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
          const items = Array.isArray(j.items) ? j.items : [];
          render(items);
          setStatus(`Loaded ${items.length} • ${j.source||"v4"} • ${rid}`);
        }

        function isLoadTopFindingsClick(ev){
          // capture any element clicked (button/div/a/span) containing the text
          const path = (ev.composedPath && ev.composedPath()) || [];
          for (const el of path){
            if (!el || !el.textContent) continue;
            const t = norm(el.textContent);
            if (t.includes("load top findings")) return true;
          }
          return false;
        }

        // Capturing listener (beats other handlers)
        document.addEventListener("click", (ev)=>{
          try{
            if (isLoadTopFindingsClick(ev)){
              ev.preventDefault();
              ev.stopPropagation();
              ensurePanel();
              load(25);
            }
          }catch(e){ console.error("[VSP][TOPFIND_PANEL_V2] click err", e); }
        }, true);

        // Ensure panel is visible even before click
        if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ensurePanel);
        else ensurePanel();

        log("installed capture+panel");
      }catch(e){
        console.error("[VSP][TOPFIND_PANEL_V2] fatal", e);
      }
    })();
    /* ===================== /VSP_P0_TOPFIND_UI_CAPTURE_PANEL_V2 ===================== */
    """).strip("\n") + "\n"
    p.write_text(s + "\n\n" + block, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

node --check static/js/vsp_dash_only_v1.js >/dev/null
echo "[OK] node --check passed"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Ctrl+Shift+R /vsp5 then click Load top findings (25). A new 'Top findings (live)' panel will show results."
