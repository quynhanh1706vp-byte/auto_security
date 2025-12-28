#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date; need systemctl

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_releasecard_v2_${TS}"
echo "[BACKUP] ${JS}.bak_releasecard_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RUNS_RELEASE_CARD_V2_FIXED_BODY_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

code = textwrap.dedent(r"""
;(()=> {
  try{
    // ===================== VSP_P1_RUNS_RELEASE_CARD_V2_FIXED_BODY_V1 =====================
    const isRuns = ()=>{
      try{
        const p = (location.pathname||"");
        if (p.includes("vsp5") || p.includes("dashboard")) return false;
        return (p === "/runs" || p.includes("/runs") || p.includes("runs_reports"));
      }catch(e){ return false; }
    };

    function ensureBox(){
      const id="vsp_current_release_card_v2";
      let box=document.getElementById(id);
      if (box) return box;
      box=document.createElement("div");
      box.id=id;
      box.style.cssText=[
        "position:fixed","right:16px","bottom:16px","z-index:99999",
        "max-width:560px","min-width:360px",
        "border:1px solid rgba(255,255,255,.14)",
        "background:rgba(10,18,32,.78)",
        "border-radius:16px","padding:12px 14px",
        "box-shadow:0 12px 34px rgba(0,0,0,.45)",
        "backdrop-filter:blur(8px)"
      ].join(";");
      document.body.appendChild(box);
      return box;
    }

    function row(label, val){
      return `<div style="display:flex;gap:10px;align-items:baseline;line-height:1.35;margin:4px 0">
        <div style="min-width:110px;opacity:.78">${label}</div>
        <div style="font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12.5px; word-break:break-all">${val}</div>
      </div>`;
    }

    async function fetchJson(url){
      const r = await fetch(url, {credentials:"same-origin", cache:"no-store"});
      if (!r.ok) throw new Error("http_"+r.status);
      return await r.json();
    }

    async function load(){
      if (!isRuns()) return;
      const box=ensureBox();
      try{
        let j = await fetchJson("/api/vsp/release_latest");
        if (!j || !j.package) throw new Error("no_package");
        const pkg=j.package, sha=j.sha256_file||"", man=j.manifest||"", ts=j.ts||"";
        box.innerHTML = `
          <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:8px">
            <div style="font-weight:800;letter-spacing:.2px">Current Release</div>
            <div style="opacity:.7;font-size:12px">${ts}</div>
          </div>
          ${row("PACKAGE", `<a href="/${pkg}" style="color:#9ad7ff;text-decoration:none">${pkg}</a>`)}
          ${sha ? row("SHA256", `<a href="/${sha}" style="color:#9ad7ff;text-decoration:none">${sha}</a>`) : ""}
          ${man ? row("MANIFEST", `<a href="/${man}" style="color:#9ad7ff;text-decoration:none">${man}</a>`) : ""}
          <div style="opacity:.55;font-size:11.5px;margin-top:8px">Auto-refresh: 60s • Runs-only • Safe overlay</div>
        `;
      }catch(e){
        box.innerHTML = `<div style="font-weight:700">Current Release</div>
          <div style="opacity:.75;margin-top:6px">not available</div>
          <div style="opacity:.55;font-size:11.5px;margin-top:8px">(${String(e&&e.message||e)})</div>`;
      }
    }

    function boot(){
      if (!isRuns()) return;
      if (window.__vsp_runs_release_card_v2_fixed) return;
      window.__vsp_runs_release_card_v2_fixed = true;
      load();
      setInterval(()=>{ try{ load(); }catch(e){} }, 60000);
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
    // ===================== /VSP_P1_RUNS_RELEASE_CARD_V2_FIXED_BODY_V1 =====================
  }catch(e){}
})();
""").strip("\n") + "\n"

p.write_text(s + ("\n" if not s.endswith("\n") else "") + code, encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check "$JS"
echo "[OK] node --check"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[OK] restarted"
