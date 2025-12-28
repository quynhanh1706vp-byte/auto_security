#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

BUNDLE="static/js/vsp_bundle_tabs5_v1.js"
AUTO="static/js/vsp_tabs4_autorid_v1.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }
[ -f "$AUTO" ] || { echo "[ERR] missing $AUTO"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE" "${BUNDLE}.bak_v9_${TS}"
cp -f "$AUTO"   "${AUTO}.bak_v9_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_v9_${TS}"
echo "[BACKUP] ${AUTO}.bak_v9_${TS}"

python3 - <<'PY'
from pathlib import Path

bundle = Path("static/js/vsp_bundle_tabs5_v1.js")
auto   = Path("static/js/vsp_tabs4_autorid_v1.js")

marker_bundle = "VSP_P1_DASH_MINICHARTS_V9_API_ONLY_SAFE_V1"
marker_auto   = "VSP_P1_AUTORID_FIX_YOUR_RID_V1"

s = bundle.read_text(encoding="utf-8", errors="replace")
if marker_bundle not in s:
    s += r"""

/* ===== VSP_P1_DASH_MINICHARTS_V9_API_ONLY_SAFE_V1 =====
   - API only (no DOM scan): /api/vsp/top_findings_v1?limit=200 (NO rid)
   - Hard timeout via AbortController
   - Very small rendering (few bars)
   - Killswitch: localStorage["vsp_minicharts_off"]="1"
*/
(function(){
  try{
    if(window.__VSP_MINICHARTS_V9_DONE) return;
    window.__VSP_MINICHARTS_V9_DONE = true;

    var OFF_KEY = "vsp_minicharts_off";
    try{
      if(String(localStorage.getItem(OFF_KEY) || "") === "1") return;
    }catch(e){}

    function cleanYourRidInUrl(){
      try{
        var u = new URL(window.location.href);
        var rid = String(u.searchParams.get("rid") || "");
        if(!rid || rid === "YOUR_RID" || rid === "null" || rid === "undefined"){
          u.searchParams.delete("rid");
          window.history.replaceState(null, "", u.toString());
        }
      }catch(e){}
    }
    cleanYourRidInUrl();

    function esc(s){
      s = String(s==null?"":s);
      return s.replace(/[&<>"']/g, function(c){
        return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c] || c);
      });
    }

    function el(html){
      var d = document.createElement("div");
      d.innerHTML = String(html || "").trim();
      return d.firstElementChild;
    }

    function ensurePanel(){
      var p = document.getElementById("vsp-minicharts-v9");
      if(p) return p;

      p = el(
        '<div id="vsp-minicharts-v9" style="margin-top:12px;border:1px solid rgba(255,255,255,.08);border-radius:12px;padding:12px;background:rgba(0,0,0,.14)">' +
          '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;">' +
            '<div style="font-weight:600;letter-spacing:.2px;">Mini Charts (safe v9)</div>' +
            '<div class="__v9meta" style="opacity:.75;font-size:12px;">loading…</div>' +
          '</div>' +
          '<div class="__v9body" style="margin-top:10px;"></div>' +
          '<div class="__v9hint" style="margin-top:8px;opacity:.55;font-size:11px;">source: /api/vsp/top_findings_v1?limit=200 (no rid)</div>' +
        '</div>'
      );

      // anchor: try put near bottom but inside main container if any
      var host =
        document.getElementById("vsp-dashboard-main") ||
        document.querySelector(".vsp-container") ||
        document.querySelector("main") ||
        document.body;

      try{ host.appendChild(p); }catch(e){ try{ document.body.appendChild(p); }catch(e2){} }
      return p;
    }

    function barRow(label, val, max){
      var pct = (max>0) ? Math.max(0, Math.min(100, (val*100.0/max))) : 0;
      return (
        '<div style="display:flex;align-items:center;gap:10px;margin:6px 0;">' +
          '<div style="width:140px;opacity:.9;font-size:12px;">'+esc(label)+'</div>' +
          '<div style="flex:1;height:10px;border-radius:999px;background:rgba(255,255,255,.06);overflow:hidden;">' +
            '<div style="height:10px;width:'+pct.toFixed(2)+'%;background:rgba(120,170,255,.55);border-radius:999px;"></div>' +
          '</div>' +
          '<div style="width:44px;text-align:right;opacity:.85;font-size:12px;">'+esc(val)+'</div>' +
        '</div>'
      );
    }

    function normalizeSev(x){
      x = String(x||"").toUpperCase().trim();
      if(x === "CRITICAL" || x === "HIGH" || x === "MEDIUM" || x === "LOW" || x === "INFO" || x === "TRACE") return x;
      return "";
    }

    async function fetchJSON(url, ms){
      var ctrl = new AbortController();
      var to = setTimeout(function(){ try{ ctrl.abort(); }catch(e){} }, ms || 2500);
      try{
        var r = await fetch(url, {cache:"no-store", credentials:"same-origin", signal: ctrl.signal, headers: {"accept":"application/json"}});
        var txt = await r.text();
        if(!r.ok) throw new Error("http_"+r.status);
        var j = null;
        try{ j = JSON.parse(txt); }catch(e){ throw new Error("bad_json"); }
        return j;
      } finally {
        clearTimeout(to);
      }
    }

    async function run(){
      var panel = ensurePanel();
      var meta = panel.querySelector(".__v9meta");
      var body = panel.querySelector(".__v9body");
      if(!body) return;

      try{
        meta.textContent = "fetching…";
        var j = await fetchJSON("/api/vsp/top_findings_v1?limit=200", 2500);

        var items = (j && j.items) ? j.items : [];
        var rid = (j && j.rid) ? String(j.rid) : "";
        var ok  = !!(j && j.ok);

        if(!ok || !Array.isArray(items) || items.length === 0){
          meta.textContent = "no data";
          body.innerHTML = '<div style="opacity:.75;font-size:12px;">No data from API (ok='+esc(ok)+', items='+esc(items.length)+').</div>';
          return;
        }

        // aggregate
        var sevCount = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
        var toolCount = Object.create(null);
        var cweCount  = Object.create(null);

        for(var i=0;i<items.length;i++){
          var it = items[i] || {};
          var sev = normalizeSev(it.severity);
          if(sev) sevCount[sev] = (sevCount[sev]||0) + 1;

          var tool = String(it.tool || "").trim() || "unknown";
          var isCH = (sev === "CRITICAL" || sev === "HIGH");
          if(isCH){
            toolCount[tool] = (toolCount[tool]||0) + 1;
          }

          var cwe = it.cwe;
          if(cwe !== null && cwe !== undefined && String(cwe).trim() !== ""){
            var k = String(cwe).trim();
            cweCount[k] = (cweCount[k]||0) + 1;
          }
        }

        var maxSev = 0;
        ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(function(k){ maxSev = Math.max(maxSev, sevCount[k]||0); });

        var toolPairs = Object.entries(toolCount).sort(function(a,b){ return (b[1]||0)-(a[1]||0); }).slice(0,8);
        var maxTool = 0;
        for(var t=0;t<toolPairs.length;t++) maxTool = Math.max(maxTool, toolPairs[t][1]||0);

        var cwePairs = Object.entries(cweCount).sort(function(a,b){ return (b[1]||0)-(a[1]||0); }).slice(0,8);
        var maxCwe = 0;
        for(var c=0;c<cwePairs.length;c++) maxCwe = Math.max(maxCwe, cwePairs[c][1]||0);

        meta.textContent = "RID=" + (rid || "(unknown)") + " • n=" + items.length;

        var html = "";
        html += '<div style="font-weight:600;opacity:.9;margin:6px 0 8px;">Severity distribution (sample)</div>';
        html += barRow("CRITICAL", sevCount.CRITICAL||0, maxSev);
        html += barRow("HIGH",     sevCount.HIGH||0,     maxSev);
        html += barRow("MEDIUM",   sevCount.MEDIUM||0,   maxSev);
        html += barRow("LOW",      sevCount.LOW||0,      maxSev);
        html += barRow("INFO",     sevCount.INFO||0,     maxSev);
        html += barRow("TRACE",    sevCount.TRACE||0,    maxSev);

        html += '<div style="height:10px;"></div>';
        html += '<div style="font-weight:600;opacity:.9;margin:6px 0 8px;">Critical/High by tool</div>';
        if(toolPairs.length === 0){
          html += '<div style="opacity:.7;font-size:12px;">No CRITICAL/HIGH tool buckets in sample.</div>';
        } else {
          toolPairs.forEach(function(p){ html += barRow(p[0], p[1], maxTool); });
        }

        html += '<div style="height:10px;"></div>';
        html += '<div style="font-weight:600;opacity:.9;margin:6px 0 8px;">Top CWE exposure</div>';
        if(cwePairs.length === 0){
          html += '<div style="opacity:.7;font-size:12px;">No CWE field in items.</div>';
        } else {
          cwePairs.forEach(function(p){ html += barRow("CWE-"+p[0], p[1], maxCwe); });
        }

        body.innerHTML = html;
      }catch(e){
        try{
          meta.textContent = "error";
          body.innerHTML =
            '<div style="opacity:.75;font-size:12px;">MiniCharts failed: '+esc(e && (e.message||e.toString()) )+
            '. You can disable via localStorage["'+OFF_KEY+'"]="1".</div>';
        }catch(e2){}
      }
    }

    // run once after layout
    setTimeout(function(){ run().catch(function(){}); }, 420);
  }catch(e){}
})();
"""
    bundle.write_text(s, encoding="utf-8")

a = auto.read_text(encoding="utf-8", errors="replace")
if marker_auto not in a:
    a += r"""

/* ===== VSP_P1_AUTORID_FIX_YOUR_RID_V1 =====
   - Remove rid=YOUR_RID from URL ASAP
   - Remove any localStorage key whose value is exactly YOUR_RID
*/
(function(){
  try{
    // clean URL
    try{
      var u = new URL(window.location.href);
      var rid = String(u.searchParams.get("rid")||"");
      if(!rid || rid === "YOUR_RID" || rid === "null" || rid === "undefined"){
        u.searchParams.delete("rid");
        window.history.replaceState(null, "", u.toString());
      }
    }catch(e){}

    // clean localStorage values "YOUR_RID"
    try{
      for(var i=localStorage.length-1;i>=0;i--){
        var k = localStorage.key(i);
        if(!k) continue;
        var v = localStorage.getItem(k);
        if(String(v||"") === "YOUR_RID"){
          localStorage.removeItem(k);
        }
      }
    }catch(e){}
  }catch(e){}
})();
"""
    auto.write_text(a, encoding="utf-8")

print("[OK] patched bundle:", marker_bundle)
print("[OK] patched autorid:", marker_auto)
PY

node --check "$BUNDLE" >/dev/null
node --check "$AUTO" >/dev/null
echo "[OK] node --check PASS: $BUNDLE"
echo "[OK] node --check PASS: $AUTO"
echo "[DONE] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp5  (không dùng ?rid=YOUR_RID)"
echo "[TIP] Nếu muốn tắt minicharts: localStorage['vsp_minicharts_off']='1' rồi refresh."
