#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need date; need cp; need grep; need python3

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_reset_${TS}"
echo "[BACKUP] ${JS}.bak_reset_${TS}"

cat > "$JS" <<'JS'
/* VSP_P1_BOOT_MINIMAL_COMMERCIAL_V1 */
(function(){
  if (window.__VSP_P1_BOOT_MINIMAL_COMMERCIAL_V1__) return;
  window.__VSP_P1_BOOT_MINIMAL_COMMERCIAL_V1__ = true;

  function $(q){ return document.querySelector(q); }
  function $all(q){ return Array.prototype.slice.call(document.querySelectorAll(q)); }

  function setText(sel, txt){
    var el = $(sel);
    if (el) el.textContent = txt;
  }

  function safeRidFromRunsJson(j){
    if (!j || typeof j !== 'object') return null;
    if (j.rid_latest && String(j.rid_latest).trim() && String(j.rid_latest) !== "N/A") return String(j.rid_latest);
    try{
      if (j.items && j.items.length && j.items[0].run_id) return String(j.items[0].run_id);
    }catch(_){}
    return null;
  }

  function xhrJson(url, cb){
    try{
      var x = new XMLHttpRequest();
      x.open("GET", url, true);
      x.setRequestHeader("Cache-Control","no-cache");
      x.onreadystatechange = function(){
        if (x.readyState !== 4) return;
        if (x.status >= 200 && x.status < 300){
          try{ cb(null, JSON.parse(x.responseText), x.status); }
          catch(e){ cb(e, null, x.status); }
        } else {
          cb(new Error("HTTP " + x.status), null, x.status);
        }
      };
      x.onerror = function(){ cb(new Error("network error"), null, 0); };
      x.send(null);
    }catch(e){
      cb(e, null, 0);
    }
  }

  function updateExportButtons(rid){
    // Buttons are often plain <button> with text CSV/TGZ/SHA or anchors; handle both.
    var btns = $all("button, a");
    btns.forEach(function(b){
      var t = (b.textContent || "").trim().toUpperCase();
      if (t === "CSV"){
        b.onclick = function(ev){ ev.preventDefault(); if(!rid) return; location.href="/api/vsp/export_csv?rid="+encodeURIComponent(rid); };
      } else if (t === "TGZ"){
        b.onclick = function(ev){ ev.preventDefault(); if(!rid) return; location.href="/api/vsp/export_tgz?rid="+encodeURIComponent(rid)+"&scope=reports"; };
      } else if (t === "SHA"){
        b.onclick = function(ev){ ev.preventDefault(); if(!rid) return; location.href="/api/vsp/sha256?rid="+encodeURIComponent(rid)+"&name=reports/run_gate_summary.json"; };
      }
    });

    // Also fix common links to Data Source if present
    $all('a[href^="/data_source"]').forEach(function(a){
      a.href = "/data_source?rid=" + encodeURIComponent(rid);
    });
  }

  function boot(){
    // If page has a live state span, use it; otherwise do nothing noisy.
    var stateEl = $("#vsp_live_runs_state");
    if (stateEl) stateEl.textContent = "RUNS: ...";

    var url = "/api/vsp/runs?limit=1&_ts=" + Date.now();
    xhrJson(url, function(err, j, status){
      if (err){
        if (stateEl) stateEl.textContent = "RUNS: DEGRADED";
        // Do NOT overwrite rid with N/A
        return;
      }
      var rid = safeRidFromRunsJson(j);
      if (!rid){
        if (stateEl) stateEl.textContent = "RUNS: DEGRADED";
        return;
      }
      window.vsp_rid_latest = rid;
      if (stateEl) stateEl.textContent = "RUNS: OK";
      updateExportButtons(rid);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
JS

echo "[OK] wrote bootjs: $JS"

# bump cache-bust in templates safely (no fancy escaping)
python3 - <<PY
from pathlib import Path
import re, os
ts=os.environ.get("TS","")
tpls=[
  "templates/vsp_5tabs_enterprise_v2.html",
  "templates/vsp_dashboard_2025.html",
  "templates/vsp_data_source_v1.html",
  "templates/vsp_rule_overrides_v1.html",
]
pat = re.compile(r'(/static/js/vsp_p1_page_boot_v1\.js)\?v=[^"]+')
for t in tpls:
  p=Path(t)
  if not p.exists(): 
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  s2, n = pat.subn(r"\\1?v="+ts, s)
  if n:
    p.write_text(s2, encoding="utf-8")
PY

echo "[OK] templates cache-bust bumped to TS=$TS"
echo "[NEXT] restart UI then Ctrl+F5 /vsp5 (or Incognito)."
