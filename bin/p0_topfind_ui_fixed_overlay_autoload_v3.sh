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
cp -f "$JS" "${JS}.bak_overlay_v3_${TS}"
echo "[BACKUP] ${JS}.bak_overlay_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap
p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_TOPFIND_OVERLAY_AUTOLOAD_V3"
if MARK in s:
    print("[SKIP] already patched")
else:
    block=textwrap.dedent(r"""
    /* ===================== VSP_P0_TOPFIND_OVERLAY_AUTOLOAD_V3 ===================== */
    (()=> {
      try{
        if (window.__vsp_topfind_overlay_v3) return;
        window.__vsp_topfind_overlay_v3 = true;

        const log=(...a)=>console.log("[VSP][TOPFIND_OVERLAY_V3]",...a);

        function esc(s){ return String(s||"").replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;" }[c])); }

        function ensureOverlay(){
          let box = document.getElementById("vsp_topfind_overlay_v3");
          if (box) return box;
          box = document.createElement("div");
          box.id = "vsp_topfind_overlay_v3";
          box.style.position = "fixed";
          box.style.right = "14px";
          box.style.bottom = "14px";
          box.style.width = "560px";
          box.style.maxWidth = "92vw";
          box.style.maxHeight = "52vh";
          box.style.overflow = "auto";
          box.style.zIndex = "2147483647";
          box.style.background = "rgba(10,14,26,0.96)";
          box.style.border = "1px solid rgba(255,255,255,0.12)";
          box.style.borderRadius = "14px";
          box.style.boxShadow = "0 10px 30px rgba(0,0,0,0.45)";
          box.style.color = "rgba(255,255,255,0.92)";
          box.style.fontFamily = "system-ui, -apple-system, Segoe UI, Roboto, Arial";
          box.style.fontSize = "13px";
          box.innerHTML = `
            <div style="display:flex;align-items:center;justify-content:space-between;padding:10px 12px;position:sticky;top:0;background:rgba(10,14,26,0.98);backdrop-filter: blur(6px);border-bottom:1px solid rgba(255,255,255,0.08);">
              <div style="font-weight:700">Top Findings (overlay)</div>
              <div style="display:flex;gap:8px;align-items:center">
                <span id="vsp_topfind_overlay_status_v3" style="opacity:.75;font-size:12px">Ready</span>
                <button id="vsp_topfind_overlay_reload_v3" style="cursor:pointer;border:1px solid rgba(255,255,255,0.18);background:rgba(255,255,255,0.06);color:rgba(255,255,255,0.9);padding:6px 10px;border-radius:10px">Reload</button>
                <button id="vsp_topfind_overlay_close_v3" style="cursor:pointer;border:1px solid rgba(255,255,255,0.18);background:rgba(255,255,255,0.06);color:rgba(255,255,255,0.9);padding:6px 10px;border-radius:10px">Close</button>
              </div>
            </div>
            <div style="padding:10px 12px">
              <table style="width:100%;border-collapse:collapse">
                <thead>
                  <tr style="opacity:.75;text-align:left">
                    <th style="padding:6px 8px;white-space:nowrap">Sev</th>
                    <th style="padding:6px 8px;white-space:nowrap">Tool</th>
                    <th style="padding:6px 8px;">Title</th>
                    <th style="padding:6px 8px;white-space:nowrap">Loc</th>
                  </tr>
                </thead>
                <tbody id="vsp_topfind_overlay_tbody_v3">
                  <tr><td colspan="4" style="padding:8px;opacity:.7">Not loaded</td></tr>
                </tbody>
              </table>
            </div>
          `;
          document.body.appendChild(box);

          document.getElementById("vsp_topfind_overlay_close_v3")?.addEventListener("click", ()=> box.remove());
          document.getElementById("vsp_topfind_overlay_reload_v3")?.addEventListener("click", ()=> load(25));

          return box;
        }

        function setStatus(msg){
          ensureOverlay();
          const el = document.getElementById("vsp_topfind_overlay_status_v3");
          if (el) el.textContent = msg;
        }

        function render(items){
          ensureOverlay();
          const tb = document.getElementById("vsp_topfind_overlay_tbody_v3");
          if (!tb) return;
          if (!items || !items.length){
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

        async function getLatestRid(){
          const r = await fetch("/api/vsp/rid_latest_gate_root", {cache:"no-store"});
          const j = await r.json();
          return (j && j.rid) ? j.rid : "";
        }

        async function load(limit=25){
          try{
            ensureOverlay();
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
            render(Array.isArray(j.items)?j.items:[]);
            setStatus(`Loaded ${(j.items||[]).length} • ${j.source||"v4"} • ${rid}`);
          }catch(e){
            console.error("[VSP][TOPFIND_OVERLAY_V3] load err", e);
            setStatus("Error (see console)");
          }
        }

        // Boot: show overlay + auto load once
        function boot(){
          ensureOverlay();
          load(25);
          log("boot ok");
        }

        if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
        else boot();

      }catch(e){
        console.error("[VSP][TOPFIND_OVERLAY_V3] fatal", e);
      }
    })();
    /* ===================== /VSP_P0_TOPFIND_OVERLAY_AUTOLOAD_V3 ===================== */
    """).strip("\n") + "\n"
    p.write_text(s + "\n\n" + block, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

node --check static/js/vsp_dash_only_v1.js >/dev/null
echo "[OK] node --check passed"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Ctrl+Shift+R /vsp5 -> overlay should appear bottom-right automatically."
