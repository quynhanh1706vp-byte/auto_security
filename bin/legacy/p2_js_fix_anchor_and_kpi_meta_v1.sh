#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_JS_ANCHOR_META_CLIENT_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
cp -f "$JS" "${JS}.bak_jsfix_${TS}"
echo "[BACKUP] ${JS}.bak_jsfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

JS = Path("static/js/vsp_dashboard_luxe_v1.js")
MARK = "VSP_P2_JS_ANCHOR_META_CLIENT_V1"
s = JS.read_text(errors="ignore")
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

patch = r"""
/* ===================== VSP_P2_JS_ANCHOR_META_CLIENT_V1 ===================== */
(function(){
  const MARK = "VSP_P2_JS_ANCHOR_META_CLIENT_V1";

  function ensureAnchor(){
    try{
      if(document.getElementById("vsp-dashboard-main")) return;
      const root = document.getElementById("vsp5_root");
      const div = document.createElement("div");
      div.id = "vsp-dashboard-main";
      if(root && root.parentNode){
        root.parentNode.insertBefore(div, root);
      }else if(document.body){
        document.body.insertBefore(div, document.body.firstChild);
      }
    }catch(e){}
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ensureAnchor);
  }else{
    ensureAnchor();
  }

  const origFetch = window.fetch;
  if(typeof origFetch === "function" && !window.__vspFetchPatched__){
    window.__vspFetchPatched__ = true;
    window.fetch = async function(input, init){
      const url = (typeof input === "string") ? input : (input && input.url) || "";
      const resp = await origFetch.call(this, input, init);
      try{
        if(url.includes("/api/vsp/run_file_allow") && url.includes("findings_unified.json")){
          const ct = (resp.headers && resp.headers.get && resp.headers.get("content-type")) || "";
          if(ct.includes("application/json")){
            const j = await resp.clone().json();
            if(j && typeof j === "object" && Array.isArray(j.findings)){
              const hasMeta = j.meta && j.meta.counts_by_severity;
              if(!hasMeta){
                const counts = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
                for(const f of j.findings){
                  const sev = (f && f.severity) ? String(f.severity).toUpperCase() : "INFO";
                  if(Object.prototype.hasOwnProperty.call(counts, sev)) counts[sev]++; else counts.INFO++;
                }
                j.meta = j.meta || {};
                j.meta.counts_by_severity = counts;
                j.__patched__ = MARK;
                const body = JSON.stringify(j);
                const headers = new Headers(resp.headers || {});
                headers.set("content-type", "application/json; charset=utf-8");
                return new Response(body, {status: resp.status, statusText: resp.statusText, headers});
              }
            }
          }
        }
      }catch(e){}
      return resp;
    };
  }
})();
/* ===================== /VSP_P2_JS_ANCHOR_META_CLIENT_V1 ===================== */
"""
JS.write_text(s + "\n\n" + patch + "\n")
print("[OK] appended JS patch:", MARK)
PY

# optional: restart service to refresh served asset if cached in gunicorn
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
fi

echo "[DONE] Now hard refresh browser: Ctrl+Shift+R"
