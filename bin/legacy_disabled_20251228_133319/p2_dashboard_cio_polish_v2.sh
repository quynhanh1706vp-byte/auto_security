#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_dashboard_luxe_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_cio_polish_${TS}"
echo "[BACKUP] ${JS}.bak_cio_polish_${TS}"

python3 - "$JS" <<'PY'
import sys, textwrap
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_DASHBOARD_CIO_POLISH_V2"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* VSP_P2_DASHBOARD_CIO_POLISH_V2 */
(function(){
  function esc(s){ return String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c])); }
  function sevBadge(sev){
    const S=(sev||"").toUpperCase();
    const map={
      "CRITICAL":["rgba(255,64,80,0.18)","rgba(255,64,80,0.55)"],
      "HIGH":["rgba(255,140,64,0.18)","rgba(255,140,64,0.55)"],
      "MEDIUM":["rgba(255,214,64,0.16)","rgba(255,214,64,0.55)"],
      "LOW":["rgba(120,200,255,0.14)","rgba(120,200,255,0.50)"],
      "INFO":["rgba(170,170,170,0.14)","rgba(170,170,170,0.45)"],
      "TRACE":["rgba(120,255,180,0.12)","rgba(120,255,180,0.45)"]
    };
    const c=map[S]||["rgba(255,255,255,0.08)","rgba(255,255,255,0.18)"];
    return `<span style="
      display:inline-flex;align-items:center;gap:6px;
      padding:4px 10px;border-radius:999px;
      background:${c[0]};border:1px solid ${c[1]};
      font-size:12px;letter-spacing:.04em">
      <span style="width:7px;height:7px;border-radius:50%;background:${c[1]}"></span>${esc(S||"—")}
    </span>`;
  }

  async function jget(url){
    const r=await fetch(url, {credentials:"same-origin"});
    const t=await r.text();
    try { return {ok:true, code:r.status, json: JSON.parse(t)}; }
    catch(e){ return {ok:false, code:r.status, text:t}; }
  }

  function upgradeTopFindings(){
    const root=document.querySelector("#vsp-cio-root");
    if(!root) return;

    // find the Top Findings card table (created by V1)
    const tables=root.querySelectorAll("table");
    if(!tables || !tables.length) return;

    // apply table polish
    for(const tb of tables){
      tb.style.borderCollapse="separate";
      tb.style.borderSpacing="0";
      tb.style.width="100%";
      const ths=tb.querySelectorAll("thead th");
      ths.forEach(th=>{
        th.style.position="sticky";
        th.style.top="0";
        th.style.background="rgba(15,18,24,0.92)";
        th.style.backdropFilter="blur(8px)";
        th.style.zIndex="1";
        th.style.borderBottom="1px solid rgba(255,255,255,0.10)";
      });

      const trs=tb.querySelectorAll("tbody tr");
      trs.forEach(tr=>{
        tr.style.transition="background 120ms ease";
        tr.addEventListener("mouseenter", ()=> tr.style.background="rgba(255,255,255,0.05)");
        tr.addEventListener("mouseleave", ()=> tr.style.background="transparent");
        const tds=tr.querySelectorAll("td");
        if(tds && tds.length){
          // first col is severity text -> replace with badge
          const sev = tds[0].textContent || "";
          tds[0].innerHTML = sevBadge(sev.trim());
        }
      });
    }
  }

  async function addExportButtons(){
    const root=document.querySelector("#vsp-cio-root");
    if(!root) return;

    // put buttons above first row
    let bar=root.querySelector('[data-testid="vsp-cio-exportbar"]');
    if(bar) return;

    const rel=await jget("/api/vsp/release_latest");
    const dl = rel.ok ? (rel.json.download_url || "") : "";
    const audit = rel.ok ? (rel.json.audit_url || "") : "";
    const manifest = rel.ok ? (rel.json.manifest_path || "") : "";

    bar=document.createElement("div");
    bar.setAttribute("data-testid","vsp-cio-exportbar");
    bar.style.cssText="display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:12px 0 4px 0";

    function btn(label, href){
      const a=document.createElement("a");
      a.textContent=label;
      a.href=href||"#";
      a.target="_blank";
      a.rel="noopener";
      a.style.cssText="display:inline-flex;align-items:center;gap:8px;padding:8px 12px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);text-decoration:none;color:inherit;font-size:13px";
      a.onmouseenter=()=>a.style.background="rgba(255,255,255,0.06)";
      a.onmouseleave=()=>a.style.background="rgba(255,255,255,0.04)";
      if(!href){ a.style.opacity="0.45"; a.onclick=(e)=>e.preventDefault(); }
      return a;
    }

    bar.appendChild(btn("Download ZIP", dl));
    bar.appendChild(btn("Open Audit", audit));
    // manifest_path is a path inside run dir; if you have an endpoint to fetch it, change here later.
    bar.appendChild(btn("Manifest (path)", manifest ? "#" : ""));

    root.prepend(bar);
  }

  function run(){
    // delay a bit to let V1 render
    setTimeout(()=>{
      addExportButtons().finally(()=>{});
      upgradeTopFindings();
    }, 350);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", run);
  else run();
})();
""")

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended CIO polish v2")
PY

node -c "$JS"
echo "[OK] node -c OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

grep -n "VSP_P2_DASHBOARD_CIO_POLISH_V2" -n "$JS" | head -n 3
