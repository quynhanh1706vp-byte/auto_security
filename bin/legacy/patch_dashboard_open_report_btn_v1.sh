#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_open_report_${TS}" && echo "[BACKUP] $F.bak_open_report_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_DASH_OPEN_REPORT_BTN_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

addon = r'''
/* VSP_DASH_OPEN_REPORT_BTN_V1: open CIO report for live RID */
(function(){
  'use strict';
  function normRid(x){
    if(!x) return "";
    return String(x).trim().replace(/^RID:\s*/i,'').replace(/^RUN_/i,'');
  }
  function getRid(){
    try{
      return normRid(localStorage.getItem("vsp_rid_selected_v2") || localStorage.getItem("vsp_rid_selected") || "");
    }catch(e){ return ""; }
  }

  function inject(){
    // try to attach near badges bar if exists; else top of body
    const host = document.getElementById("vsp-dash-p1-badges") || document.body;
    if(!host) return;

    if(document.getElementById("vsp-open-cio-report-btn")) return;

    const btn = document.createElement("button");
    btn.id = "vsp-open-cio-report-btn";
    btn.textContent = "Open CIO Report";
    btn.style.cssText = "margin-left:10px; padding:8px 10px; border-radius:10px; font-size:12px; border:1px solid rgba(148,163,184,.35); background:rgba(2,6,23,.55); color:#e2e8f0; cursor:pointer;";
    btn.addEventListener("click", function(){
      const rid = getRid();
      if(!rid){ alert("No RID selected"); return; }
      window.open("/vsp/report_cio_v1/" + encodeURIComponent(rid), "_blank", "noopener");
    });

    // put into badges bar if possible
    if(host && host.id === "vsp-dash-p1-badges"){
      host.appendChild(btn);
    }else{
      document.body.insertBefore(btn, document.body.firstChild);
    }
  }

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", inject);
  else inject();
})();
'''
p.write_text(s.rstrip()+"\n\n"+MARK+"\n"+addon+"\n", encoding="utf-8")
print("[OK] appended dashboard open report button")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_dashboard_open_report_btn_v1"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
