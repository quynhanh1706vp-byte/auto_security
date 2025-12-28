#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_exports_${TS}"
echo "[BACKUP] ${JS}.bak_exports_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_EXPORTS_EVIDENCE_MODAL_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* ===================== VSP_P1_DASH_EXPORTS_EVIDENCE_MODAL_V1 ===================== */
(()=> {
  try{
    if (!(location && location.pathname === "/vsp5")) return;

    const css = `
#vsp_exp_btn_v1{
  cursor:pointer; border:1px solid rgba(255,255,255,.14);
  background:rgba(255,255,255,.06); color:rgba(255,255,255,.92);
  padding:7px 10px; border-radius:12px; font-weight:900;
}
#vsp_copyrid_btn_v1{
  cursor:pointer; border:1px solid rgba(255,255,255,.14);
  background:rgba(255,255,255,.06); color:rgba(255,255,255,.92);
  padding:7px 10px; border-radius:12px; font-weight:900;
}
#vsp_exp_modal_v1{
  position:fixed; inset:0; z-index:120000;
  background:rgba(0,0,0,.55); display:none; align-items:center; justify-content:center;
}
#vsp_exp_modal_v1 .card{
  width:min(940px, 94vw); max-height:82vh; overflow:auto;
  border-radius:16px;
  background:rgba(10,16,32,.96);
  border:1px solid rgba(255,255,255,.12);
  box-shadow:0 18px 55px rgba(0,0,0,.55);
  padding:14px;
  color:rgba(255,255,255,.92);
  font:12px/1.4 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial;
}
#vsp_exp_modal_v1 .top{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px}
#vsp_exp_modal_v1 .ttl{font-weight:900;letter-spacing:.2px}
#vsp_exp_modal_v1 button{
  cursor:pointer;border:1px solid rgba(255,255,255,.14);
  background:rgba(255,255,255,.06); color:rgba(255,255,255,.92);
  padding:7px 10px;border-radius:12px;font-weight:900;
}
#vsp_exp_modal_v1 .grid{display:grid; grid-template-columns: 1fr 1fr; gap:10px}
#vsp_exp_modal_v1 .item{
  border:1px solid rgba(255,255,255,.10);
  background:rgba(255,255,255,.04);
  border-radius:14px;
  padding:10px;
}
#vsp_exp_modal_v1 .item .h{font-weight:900; margin-bottom:6px}
#vsp_exp_modal_v1 a{
  color:rgba(255,255,255,.90);
  text-decoration:none;
  border-bottom:1px dashed rgba(255,255,255,.22);
}
#vsp_exp_modal_v1 a:hover{border-bottom-color:rgba(255,255,255,.55)}
#vsp_exp_modal_v1 .muted{opacity:.72}
    `.trim();

    const ensureStyle=()=>{
      if (document.getElementById("vsp_exp_style_v1")) return;
      const st=document.createElement("style");
      st.id="vsp_exp_style_v1";
      st.textContent=css;
      document.head.appendChild(st);
    };

    const isRid=(v)=>{
      if (!v) return false;
      v=String(v).trim();
      if (v.length<6||v.length>80) return false;
      if (/\s/.test(v)) return false;
      if (!/^[A-Za-z0-9][A-Za-z0-9_.:-]+$/.test(v)) return false;
      if (!/\d/.test(v)) return false;
      return true;
    };

    const getRid=()=>{
      const v=(window.__vsp_last_rid_v1||"").trim();
      return isRid(v)?v:"";
    };

    const runFileUrl=(rid, path)=>`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;

    const ensureModal=()=>{
      ensureStyle();
      if (document.getElementById("vsp_exp_modal_v1")) return;
      const m=document.createElement("div");
      m.id="vsp_exp_modal_v1";
      m.innerHTML=`
        <div class="card">
          <div class="top">
            <div class="ttl" id="vsp_exp_ttl_v1">Exports & Evidence</div>
            <button id="vsp_exp_close_v1">Close</button>
          </div>
          <div class="muted" id="vsp_exp_rid_v1" style="margin-bottom:10px">RID: —</div>
          <div class="grid" id="vsp_exp_grid_v1"></div>
        </div>
      `;
      document.body.appendChild(m);
      m.addEventListener("click",(e)=>{ if(e.target===m) m.style.display="none"; });
      document.getElementById("vsp_exp_close_v1").addEventListener("click",()=>{ m.style.display="none"; });
    };

    const openModal=()=>{
      ensureModal();
      const rid=getRid();
      const m=document.getElementById("vsp_exp_modal_v1");
      const ridEl=document.getElementById("vsp_exp_rid_v1");
      const grid=document.getElementById("vsp_exp_grid_v1");
      const ttl=document.getElementById("vsp_exp_ttl_v1");
      if (!rid){
        ttl.textContent="Exports & Evidence";
        ridEl.textContent="RID: (not ready) — bấm Refresh/Pin RID trước";
        grid.innerHTML=`<div class="item"><div class="h">Tip</div><div class="muted">Hãy bấm Refresh hoặc Pin RID để Dashboard có RID, rồi mở lại Export.</div></div>`;
        m.style.display="flex";
        return;
      }
      ttl.textContent="Exports & Evidence";
      ridEl.textContent=`RID: ${rid}`;
      const items = [
        ["Gate summary", [
          ["run_gate_summary.json","run_gate_summary.json"],
          ["run_gate.json","run_gate.json"],
        ]],
        ["Unified findings", [
          ["findings_unified.json","findings_unified.json"],
          ["reports/findings_unified.csv","reports/findings_unified.csv"],
          ["reports/findings_unified.sarif","reports/findings_unified.sarif"],
          ["reports/findings_unified.json","reports/findings_unified.json"],
        ]],
        ["Per-tool summaries", [
          ["semgrep_summary.json","semgrep_summary.json"],
          ["gitleaks_summary.json","gitleaks_summary.json"],
          ["kics_summary.json","kics_summary.json"],
          ["trivy_summary.json","trivy_summary.json"],
          ["syft_summary.json","syft_summary.json"],
          ["grype_summary.json","grype_summary.json"],
          ["bandit_summary.json","bandit_summary.json"],
          ["codeql_summary.json","codeql_summary.json"],
        ]],
        ["Evidence index", [
          ["run_manifest.json","run_manifest.json"],
          ["run_evidence_index.json","run_evidence_index.json"],
          ["SUMMARY.txt","SUMMARY.txt"],
        ]],
      ];

      grid.innerHTML = "";
      for (const [title, links] of items){
        const box=document.createElement("div");
        box.className="item";
        const html = links.map(([label,path])=>{
          const u = runFileUrl(rid, path);
          return `<div style="margin:4px 0"><a href="${u}" target="_blank" rel="noopener noreferrer">${label}</a> <span class="muted">(${path})</span></div>`;
        }).join("");
        box.innerHTML = `<div class="h">${title}</div>${html}`;
        grid.appendChild(box);
      }
      m.style.display="flex";
    };

    const copyRid=async()=>{
      const rid=getRid();
      if (!rid) return;
      try{ await navigator.clipboard.writeText(rid); }catch(e){}
    };

    const injectButtons=()=>{
      const cmd=document.getElementById("vsp_cmdbar_v1");
      if (!cmd) return false;

      // Put buttons on RHS near existing actions
      const rhs = cmd.querySelector(".rhs") || cmd;

      if (!document.getElementById("vsp_copyrid_btn_v1")){
        const b=document.createElement("button");
        b.id="vsp_copyrid_btn_v1";
        b.textContent="Copy RID";
        b.onclick=()=>copyRid();
        rhs.insertAdjacentElement("afterbegin", b);
      }

      if (!document.getElementById("vsp_exp_btn_v1")){
        const b=document.createElement("button");
        b.id="vsp_exp_btn_v1";
        b.textContent="Export";
        b.onclick=()=>openModal();
        rhs.insertAdjacentElement("afterbegin", b);
      }
      return true;
    };

    const boot=()=>{
      if (!(location && location.pathname==="/vsp5")) return;
      let n=0;
      const t=setInterval(()=>{
        n++;
        if (injectButtons()){ clearInterval(t); }
        if (n>120) clearInterval(t);
      }, 250);
    };

    if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot, {once:true});
    else boot();

  }catch(e){
    console.error("[VSP_EXPORT_MODAL_V1] fatal", e);
  }
})();
/* ===================== /VSP_P1_DASH_EXPORTS_EVIDENCE_MODAL_V1 ===================== */
""").rstrip()+"\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null && echo "[OK] node --check: $JS" || { echo "[ERR] node --check failed"; exit 3; }
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 => Export + Copy RID buttons appear on topbar."
