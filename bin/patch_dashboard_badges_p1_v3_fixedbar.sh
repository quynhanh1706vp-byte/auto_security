#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_badges_v3_${TS}" && echo "[BACKUP] $F.bak_badges_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_DASH_BADGES_P1_V3_FIXEDBAR"
if MARK in s:
    print("[SKIP] already patched v3")
    raise SystemExit(0)

block = r'''
/* VSP_DASH_BADGES_P1_V3_FIXEDBAR: ensure badges visible even if dashboard host selector mismatch */
(function(){
  'use strict';

  function _pickHost(){
    // 1) container that holds KPI cards
    const card = document.querySelector(".vsp-card, .dashboard-card, .card");
    if(card && card.parentElement) return card.parentElement;

    // 2) active tab pane (common patterns)
    const active = document.querySelector(".tab-pane.active, .tab-content .active, [role='tabpanel'][aria-hidden='false']");
    if(active) return active;

    // 3) main content region
    return document.querySelector("main") || document.body;
  }

  function _ensureFixedStyle(){
    if(document.getElementById("vsp-dash-fixed-style")) return;
    const st = document.createElement("style");
    st.id="vsp-dash-fixed-style";
    st.textContent = `
      #vsp-dash-p1-badges{ z-index:9999; }
      #vsp-dash-p1-badges.vsp-fixed{
        position: sticky;
        top: 0;
        backdrop-filter: blur(8px);
        background: rgba(2,6,23,.60) !important;
      }
    `;
    document.head.appendChild(st);
  }

  // override ensureBar from V1 (if exists) by recreating bar + sticky class
  function ensureBarV3(){
    _ensureFixedStyle();
    let bar = document.getElementById("vsp-dash-p1-badges");
    if(bar) {
      bar.classList.add("vsp-fixed");
      return bar;
    }
    const host = _pickHost();
    if(!host) return null;

    bar = document.createElement("div");
    bar.id = "vsp-dash-p1-badges";
    bar.className = "vsp-fixed";
    bar.style.cssText = "margin:0 0 12px 0;padding:10px 12px;border:1px solid rgba(148,163,184,.18);border-radius:14px;background:rgba(2,6,23,.35);display:flex;gap:10px;flex-wrap:wrap;align-items:center;";

    function pill(id, label){
      const a = document.createElement("a");
      a.href="#";
      a.id=id;
      a.style.cssText = "display:inline-flex;gap:8px;align-items:center;padding:7px 10px;border-radius:999px;border:1px solid rgba(148,163,184,.22);text-decoration:none;color:#cbd5e1;font-size:12px;white-space:nowrap;";
      a.innerHTML = `<b style="font-weight:700;color:#e2e8f0">${label}</b><span style="opacity:.9" data-val>loading…</span>`;
      return a;
    }

    bar.appendChild(pill("vsp-pill-degraded","Degraded"));
    bar.appendChild(pill("vsp-pill-overrides","Overrides"));
    bar.appendChild(pill("vsp-pill-rid","RID"));

    host.prepend(bar);
    return bar;
  }

  // kick once after load to guarantee visibility
  window.addEventListener("load", function(){
    setTimeout(()=>{ try{ ensureBarV3(); }catch(e){} }, 200);
  });
  window.addEventListener("hashchange", function(){
    setTimeout(()=>{ try{ ensureBarV3(); }catch(e){} }, 120);
  });
  window.addEventListener("vsp:rid_changed", function(){
    setTimeout(()=>{ try{ ensureBarV3(); }catch(e){} }, 50);
  });
})();
'''

p.write_text(s.rstrip()+"\n\n"+block+"\n", encoding="utf-8")
print("[OK] appended v3 fixedbar block")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_dashboard_badges_p1_v3_fixedbar"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
