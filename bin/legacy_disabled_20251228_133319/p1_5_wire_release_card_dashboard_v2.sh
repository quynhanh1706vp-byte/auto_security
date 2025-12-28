#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_releaseui_v2_${TS}"
echo "[BACKUP] ${JS}.bak_releaseui_v2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_5_RELEASE_CARD_WIRE_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
/* VSP_P1_5_RELEASE_CARD_WIRE_V2
   Robust inject: wait for dashboard DOM, observe mutations, then inject card into best anchor.
*/
(function(){
  const CARD_ID = "vsp-release-latest-card";
  const MAX_MS = 12000;

  function _abs(u){
    try{
      if(!u) return "";
      if(u.startsWith("http://") || u.startsWith("https://")) return u;
      if(u.startsWith("/")) return u;
      return "/" + u;
    }catch(e){ return u||""; }
  }

  async function _load(){
    try{
      const r = await fetch("/api/vsp/release_latest", {cache:"no-store"});
      if(!r.ok) return null;
      const j = await r.json();
      if(!j || !j.ok) return null;
      return j;
    }catch(e){ return null; }
  }

  function _findAnchor(){
    // 1) explicit dashboard containers
    const cands = [
      document.querySelector("#vsp-dashboard-main"),
      document.querySelector("#vsp-dashboard"),
      document.querySelector("[data-vsp-page='dashboard']"),
      document.querySelector("main"),
      document.body
    ].filter(Boolean);

    // 2) try to locate a “Top Findings” block and insert right before it
    try{
      const all = Array.from(document.querySelectorAll("h1,h2,h3,div,section"));
      const tf = all.find(el => (el.textContent||"").trim().toLowerCase() === "top findings");
      if(tf && tf.parentElement) return tf.parentElement;
    }catch(e){}

    return cands[0] || document.body;
  }

  function _render(j){
    if(document.getElementById(CARD_ID)) return; // no dup
    const a = _findAnchor();
    if(!a) return;

    const rid = String(j.rid || "");
    const dl = _abs(j.download_url || "");
    const au0 = _abs(j.audit_url || "");
    const au = (au0 && au0 !== "/") ? au0 : ("/api/vsp/release_audit?rid=" + encodeURIComponent(rid));

    const div = document.createElement("div");
    div.id = CARD_ID;
    div.style.cssText = [
      "margin:12px 0",
      "padding:12px 14px",
      "border:1px solid rgba(255,255,255,.12)",
      "border-radius:12px",
      "background:rgba(255,255,255,.04)",
      "display:flex",
      "align-items:center",
      "justify-content:space-between",
      "gap:12px",
      "position:relative",
      "z-index:2"
    ].join(";");

    div.innerHTML = `
      <div style="min-width:0">
        <div style="font-weight:750;letter-spacing:.2px">Latest Release</div>
        <div style="opacity:.85;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">RID: ${rid}</div>
      </div>
      <div style="display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end">
        <a href="${dl}" style="text-decoration:none;padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.16);background:rgba(255,255,255,.06);font-size:12px">Download</a>
        <a href="${au}" style="text-decoration:none;padding:8px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.16);background:rgba(255,255,255,.06);font-size:12px">Audit</a>
      </div>
    `;

    // Prefer prepend to keep it visible at top
    try{
      if(a.firstElementChild) a.insertBefore(div, a.firstElementChild);
      else a.appendChild(div);
    }catch(e){
      document.body.insertBefore(div, document.body.firstChild);
    }
  }

  function _boot(){
    const t0 = Date.now();

    const tick = async () => {
      if(document.getElementById(CARD_ID)) return true;
      const j = await _load();
      if(j){
        _render(j);
        if(document.getElementById(CARD_ID)) return true;
      }
      return false;
    };

    // Try immediately, then observe DOM changes until inserted or timeout
    tick();

    const obs = new MutationObserver(() => {
      if(Date.now() - t0 > MAX_MS){
        try{ obs.disconnect(); }catch(e){}
        return;
      }
      tick();
    });

    try{
      obs.observe(document.documentElement || document.body, {childList:true, subtree:true});
    }catch(e){}

    // hard stop
    setTimeout(() => { try{ obs.disconnect(); }catch(e){} }, MAX_MS + 200);
  }

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", _boot);
  else _boot();
})();
'''.strip("\n") + "\n"

p.write_text(s + "\n\n" + inject, encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check: syntax OK"
grep -n "VSP_P1_5_RELEASE_CARD_WIRE_V2" "$JS" | head -n 2 && echo "[OK] marker present"
