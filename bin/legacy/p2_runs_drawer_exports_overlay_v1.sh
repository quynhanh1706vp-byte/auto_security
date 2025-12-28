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
cp -f "$JS" "${JS}.bak_runsexport_${TS}"
echo "[BACKUP] ${JS}.bak_runsexport_${TS}"

python3 - "$JS" <<'PY'
import sys, textwrap
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_RUNS_DRAWER_EXPORTS_OVERLAY_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* VSP_P2_RUNS_DRAWER_EXPORTS_OVERLAY_V1 */
(function(){
  function isRuns(){ return String(location.pathname||"").includes("/runs"); }
  async function jget(url){
    const r=await fetch(url, {credentials:"same-origin"});
    const t=await r.text();
    try { return {ok:true, json: JSON.parse(t)}; } catch(e){ return {ok:false, text:t, code:r.status}; }
  }
  function esc(s){ return String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c])); }

  function ensureOverlay(){
    let ov=document.querySelector('[data-testid="runs-overlay"]');
    if(ov) return ov;

    ov=document.createElement("div");
    ov.setAttribute("data-testid","runs-overlay");
    ov.style.cssText=[
      "position:fixed","inset:0","background:rgba(0,0,0,0.55)",
      "z-index:10000","display:none","align-items:center","justify-content:center",
      "padding:18px"
    ].join(";");

    ov.innerHTML=`
      <div style="width:min(1200px, 96vw); height:min(90vh, 900px); background:rgba(15,18,24,0.98);
                  border:1px solid rgba(255,255,255,0.10); border-radius:16px; overflow:hidden;
                  box-shadow:0 20px 60px rgba(0,0,0,0.55); display:flex; flex-direction:column">
        <div style="padding:10px 12px; display:flex; align-items:center; justify-content:space-between;
                    border-bottom:1px solid rgba(255,255,255,0.10); gap:10px">
          <div data-testid="runs-overlay-title" style="font-weight:800; font-size:13px; opacity:.9">Viewer</div>
          <div style="display:flex; gap:10px; align-items:center">
            <a data-testid="runs-overlay-opennew" href="#" target="_blank" rel="noopener"
               style="padding:7px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);
                      background:rgba(255,255,255,0.04);text-decoration:none;color:inherit;font-size:12px">Open new tab</a>
            <button data-testid="runs-overlay-close"
               style="padding:7px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);
                      background:rgba(255,255,255,0.04);color:inherit;cursor:pointer;font-size:12px">Close</button>
          </div>
        </div>
        <iframe data-testid="runs-overlay-frame" src="about:blank"
                style="border:0; width:100%; height:100%; background:#0b0f14"></iframe>
      </div>
    `;
    document.body.appendChild(ov);

    ov.querySelector('[data-testid="runs-overlay-close"]').onclick=()=>{ ov.style.display="none"; };
    ov.addEventListener("click",(e)=>{ if(e.target===ov) ov.style.display="none"; });
    document.addEventListener("keydown",(e)=>{ if(e.key==="Escape") ov.style.display="none"; });

    return ov;
  }

  function openOverlay(title, url){
    const ov=ensureOverlay();
    ov.querySelector('[data-testid="runs-overlay-title"]').textContent=title||"Viewer";
    ov.querySelector('[data-testid="runs-overlay-opennew"]').href=url;
    ov.querySelector('[data-testid="runs-overlay-frame"]').src=url;
    ov.style.display="flex";
  }

  // Helper: find a file under a RID via run_file_allow trying multiple common paths
  async function pickFile(rid, paths){
    for(const p of paths){
      const res=await jget(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(p)}&limit=1`);
      if(res.ok && res.json && res.json.ok){
        return p;
      }
    }
    return null;
  }

  async function enrichDrawer(rid){
    const d=document.querySelector('[data-testid="runs-drawer"]');
    if(!d) return;

    // Add export section if not exists
    let box=d.querySelector('[data-testid="runs-drawer-exports"]');
    if(!box){
      box=document.createElement("div");
      box.setAttribute("data-testid","runs-drawer-exports");
      box.style.cssText="padding:10px 14px;border-top:1px solid rgba(255,255,255,0.10);display:flex;gap:10px;flex-wrap:wrap";
      box.innerHTML=`
        <button data-testid="runs-exp-zip"
          style="padding:8px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit;cursor:pointer;font-size:12px">Download ZIP</button>
        <button data-testid="runs-exp-html"
          style="padding:8px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit;cursor:pointer;font-size:12px">Open HTML</button>
        <button data-testid="runs-exp-pdf"
          style="padding:8px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit;cursor:pointer;font-size:12px">Open PDF</button>
        <a data-testid="runs-exp-audit" href="#" target="_blank" rel="noopener"
          style="display:inline-flex;align-items:center;gap:8px;padding:8px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);text-decoration:none;color:inherit;font-size:12px">Open Audit</a>
        <div data-testid="runs-exp-hint" style="opacity:.7;font-size:12px;align-self:center">—</div>
      `;
      d.appendChild(box);
    }

    const hint=box.querySelector('[data-testid="runs-exp-hint"]');
    hint.textContent="Resolving exports…";

    // release_latest gives audit_url + download_url (global latest package)
    const rel=await jget("/api/vsp/release_latest");
    const auditUrl = (rel.ok && rel.json && rel.json.audit_url) ? rel.json.audit_url : "#";
    const zipUrl   = (rel.ok && rel.json && rel.json.download_url) ? rel.json.download_url : null;
    const zipBtn=box.querySelector('[data-testid="runs-exp-zip"]');
    const auditA=box.querySelector('[data-testid="runs-exp-audit"]');
    auditA.href = auditUrl || "#";
    auditA.style.opacity = auditUrl && auditUrl !== "#" ? "1" : "0.45";

    // ZIP: if we have download_url, open it; else disable
    zipBtn.onclick=()=>{
      if(zipUrl) window.open(zipUrl, "_blank", "noopener");
    };
    zipBtn.style.opacity = zipUrl ? "1" : "0.45";

    // Try find HTML/PDF under this RID (common report names)
    const htmlPaths=[
      "reports/report.html","reports/index.html","reports/summary.html","reports/vsp_report.html",
      "report/report.html","report/index.html"
    ];
    const pdfPaths=[
      "reports/report.pdf","reports/vsp_report.pdf","report/report.pdf","report/vsp_report.pdf"
    ];

    const htmlPath=await pickFile(rid, htmlPaths);
    const pdfPath=await pickFile(rid, pdfPaths);

    const htmlBtn=box.querySelector('[data-testid="runs-exp-html"]');
    const pdfBtn=box.querySelector('[data-testid="runs-exp-pdf"]');

    htmlBtn.style.opacity = htmlPath ? "1" : "0.45";
    pdfBtn.style.opacity  = pdfPath  ? "1" : "0.45";

    htmlBtn.onclick=()=>{
      if(!htmlPath) return;
      const url=`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(htmlPath)}&limit=200000`;
      openOverlay("HTML Report · "+rid, url);
    };
    pdfBtn.onclick=()=>{
      if(!pdfPath) return;
      const url=`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(pdfPath)}&limit=200000`;
      openOverlay("PDF Report · "+rid, url);
    };

    hint.textContent = `ZIP:${zipUrl? "OK":"—"} · HTML:${htmlPath? esc(htmlPath):"—"} · PDF:${pdfPath? esc(pdfPath):"—"}`;
  }

  // Hook: whenever drawer opens (we detect rid text change), enrich exports
  function boot(){
    if(!isRuns()) return;
    const d=document.querySelector('[data-testid="runs-drawer"]');
    if(!d) return;

    let lastRid="";
    const obs=new MutationObserver(()=>{
      const ridEl=d.querySelector('[data-testid="runs-drawer-rid"]');
      const rid=(ridEl && ridEl.textContent) ? ridEl.textContent.trim() : "";
      if(rid && rid !== "—" && rid !== lastRid){
        lastRid=rid;
        enrichDrawer(rid).catch(()=>{});
      }
    });
    obs.observe(d, {subtree:true, childList:true, characterData:true});
  }

  if(isRuns()){
    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
  }
})();
""")

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended exports+overlay v1")
PY

node -c "$JS"
echo "[OK] node -c OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

echo "== verify marker in served JS =="
curl -fsS "$BASE/static/js/$(basename "$JS")" | grep -n "VSP_P2_RUNS_DRAWER_EXPORTS_OVERLAY_V1" | head -n 2
