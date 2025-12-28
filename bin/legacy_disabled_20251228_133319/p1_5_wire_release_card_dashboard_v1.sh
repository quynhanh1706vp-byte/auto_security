#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep; need sed

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_releaseui_${TS}"
echo "[BACKUP] ${JS}.bak_releaseui_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_5_RELEASE_CARD_WIRE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
/* VSP_P1_5_RELEASE_CARD_WIRE_V1
   Dashboard: fetch /api/vsp/release_latest and render a small "Latest Release" card.
   Safe: if DOM anchor not found, do nothing.
*/
(function(){
  function _vspAbs(u){
    try{
      if(!u) return "";
      if(u.startsWith("http://") || u.startsWith("https://")) return u;
      if(u.startsWith("/")) return u;
      return "/" + u;
    }catch(e){ return u||""; }
  }

  async function _vspLoadReleaseLatest(){
    try{
      const r = await fetch("/api/vsp/release_latest", {cache:"no-store"});
      if(!r.ok) return null;
      const j = await r.json();
      if(!j || !j.ok) return null;
      return j;
    }catch(e){ return null; }
  }

  function _vspFindAnchor(){
    // Prefer a top area near KPIs / headline
    return document.querySelector("#vsp-dashboard-main") ||
           document.querySelector("main") ||
           document.body;
  }

  function _vspRenderReleaseCard(j){
    const a = _vspFindAnchor();
    if(!a) return;

    // avoid duplicates
    if(document.getElementById("vsp-release-latest-card")) return;

    const rid = (j.rid || "").toString();
    const dl = _vspAbs(j.download_url || "");
    const au = _vspAbs(j.audit_url || "");

    const div = document.createElement("div");
    div.id = "vsp-release-latest-card";
    div.style.cssText = "margin:12px 0;padding:12px 14px;border:1px solid rgba(255,255,255,.10);border-radius:12px;background:rgba(255,255,255,.04);display:flex;align-items:center;justify-content:space-between;gap:12px;";

    div.innerHTML = `
      <div style="min-width:0">
        <div style="font-weight:700;letter-spacing:.2px">Latest Release</div>
        <div style="opacity:.8;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">RID: ${rid}</div>
      </div>
      <div style="display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end">
        <a id="vsp-release-dl" href="${dl}" style="text-decoration:none;padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);font-size:12px">Download</a>
        <a id="vsp-release-au" href="${au}" style="text-decoration:none;padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);font-size:12px">Audit</a>
      </div>
    `;

    // Insert near top of dashboard (prepend)
    try{
      if(a.firstElementChild) a.insertBefore(div, a.firstElementChild);
      else a.appendChild(div);
    }catch(e){
      a.appendChild(div);
    }

    // If audit_url missing, fallback to release_audit?rid=...
    const auEl = document.getElementById("vsp-release-au");
    if(auEl && (!au || au === "/")){
      auEl.href = "/api/vsp/release_audit?rid=" + encodeURIComponent(rid);
    }
  }

  function _vspBoot(){
    _vspLoadReleaseLatest().then(j => { if(j) _vspRenderReleaseCard(j); });
  }

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", _vspBoot);
  else _vspBoot();
})();
'''.strip("\n") + "\n"

# Append at end (safe)
s2 = s + "\n\n" + inject
p.write_text(s2, encoding="utf-8", errors="replace")
print("[OK] patched:", MARK)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check: syntax OK"
grep -n "VSP_P1_5_RELEASE_CARD_WIRE_V1" "$JS" | head -n 2 && echo "[OK] marker present"
