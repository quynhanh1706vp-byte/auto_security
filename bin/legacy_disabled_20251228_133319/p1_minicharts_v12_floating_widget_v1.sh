#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BUNDLE="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE" "${BUNDLE}.bak_v12_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_v12_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Trim from V11 marker if present (replace old block cleanly)
m11 = "/* ===== VSP_P1_DASH_MINICHARTS_V11_SELF_HOSTED_PANEL_API_ONLY_V1 ====="
i = s.find(m11)
if i != -1:
    s = s[:i].rstrip() + "\n\n"
    print("[OK] removed old V11 block at byte", i)

v12 = r'''
/* ===== VSP_P1_DASH_MINICHARTS_V12_FLOATING_WIDGET_API_ONLY_V1 =====
   - Always visible floating widget (no DOM dependency).
   - API-only: /api/vsp/top_findings_v1?limit=200 (NO rid).
   - Ultra-light render (no loops/observers).
   - Close button sets localStorage.vsp_minicharts_off=1.
   - Debug: ?mcdebug=1 or localStorage.vsp_debug_minicharts=1
*/
(function(){
  try{
    if(window.__VSP_MINICHARTS_V12_DONE) return;
    window.__VSP_MINICHARTS_V12_DONE = true;

    function isDebug(){
      try{ if(String(localStorage.getItem("vsp_debug_minicharts")||"")==="1") return true; }catch(e){}
      try{ return String(location.search||"").indexOf("mcdebug=1")!==-1; }catch(e){}
      return false;
    }
    function dbg(){ if(isDebug()) try{ console.log.apply(console, arguments); }catch(e){} }

    // kill switch (unless forced)
    var forced = false;
    try{ forced = String(location.search||"").indexOf("mcforce=1")!==-1; }catch(e){}
    if(!forced){
      try{
        if(String(localStorage.getItem("vsp_minicharts_off")||"")==="1"){
          dbg("[V12] disabled by vsp_minicharts_off");
          return;
        }
      }catch(e){}
    }

    function esc(x){
      x = (x===null || x===undefined) ? "" : String(x);
      return x.replace(/[&<>"]/g, function(c){
        return c==="&" ? "&amp;" : c==="<" ? "&lt;" : c===">" ? "&gt;" : "&quot;";
      });
    }
    function normSev(s){
      s = (s===null || s===undefined) ? "" : String(s).trim().toUpperCase();
      if(!s) return "INFO";
      if(s.includes("CRIT")) return "CRITICAL";
      if(s.includes("HIGH")) return "HIGH";
      if(s.includes("MED"))  return "MEDIUM";
      if(s.includes("LOW"))  return "LOW";
      if(s.includes("TRACE"))return "TRACE";
      if(s.includes("INFO")) return "INFO";
      return s;
    }

    async function fetchJSON(url, ms){
      var ctl=null, t=null;
      try{ ctl = new AbortController(); }catch(e){ ctl=null; }
      try{
        if(ctl) t = setTimeout(function(){ try{ ctl.abort(); }catch(e){} }, ms||2500);
        var res = await fetch(url, { cache:"no-store", signal: ctl ? ctl.signal : undefined });
        return await res.json();
      } finally {
        if(t) clearTimeout(t);
      }
    }

    function barRow(label, val, maxVal){
      val = Number(val||0);
      maxVal = Number(maxVal||0);
      var pct = maxVal>0 ? Math.max(0, Math.min(100, Math.round((val/maxVal)*100))) : 0;
      return (
        '<div style="display:flex;align-items:center;gap:8px;margin:6px 0;">' +
          '<div style="width:86px;opacity:.85;font-size:12px;">'+esc(label)+'</div>' +
          '<div style="flex:1;height:10px;background:rgba(255,255,255,.08);border-radius:999px;overflow:hidden;">' +
            '<div style="height:10px;width:'+pct+'%;background:rgba(255,255,255,.30);border-radius:999px;"></div>' +
          '</div>' +
          '<div style="width:42px;text-align:right;opacity:.9;font-size:12px;font-variant-numeric:tabular-nums;">'+esc(val)+'</div>' +
        '</div>'
      );
    }

    function compute(items){
      var sevCount = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      var toolCH = {};
      var cweCount = {};
      for(var i=0;i<items.length;i++){
        var it = items[i] || {};
        var sev = normSev(it.severity);
        if(!(sev in sevCount)) sev = "INFO";
        sevCount[sev] = (sevCount[sev]||0) + 1;

        var tool = (it.tool===null || it.tool===undefined) ? "unknown" : String(it.tool);
        if(sev === "CRITICAL" || sev === "HIGH"){
          toolCH[tool] = (toolCH[tool]||0) + 1;
        }

        var cwe = it.cwe;
        if(cwe!==null && cwe!==undefined && String(cwe).trim()!==""){
          var k = String(cwe).trim();
          cweCount[k] = (cweCount[k]||0) + 1;
        }
      }
      var topTools = Object.entries(toolCH).sort(function(a,b){ return (b[1]||0)-(a[1]||0); }).slice(0,6);
      var topCWE = Object.entries(cweCount).sort(function(a,b){ return (b[1]||0)-(a[1]||0); }).slice(0,6);
      return { sevCount: sevCount, topTools: topTools, topCWE: topCWE };
    }

    function ensureWidget(){
      var id="__vsp_minicharts_v12_widget";
      var el=document.getElementById(id);
      if(el) return el;

      el=document.createElement("div");
      el.id=id;
      el.style.cssText=[
        "position:fixed",
        "right:16px",
        "bottom:16px",
        "width:380px",
        "max-width:calc(100vw - 32px)",
        "max-height:62vh",
        "overflow:auto",
        "z-index:2147483000",
        "border-radius:14px",
        "border:1px solid rgba(255,255,255,.10)",
        "background:rgba(0,0,0,.35)",
        "backdrop-filter: blur(8px)",
        "box-shadow: 0 12px 40px rgba(0,0,0,.45)",
        "padding:10px 12px",
        "color:rgba(255,255,255,.92)",
        "font-family: system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Arial"
      ].join(";");

      el.innerHTML =
        '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;">' +
          '<div style="font-weight:650;letter-spacing:.2px;">Mini Charts</div>' +
          '<div style="display:flex;align-items:center;gap:8px;">' +
            '<div style="opacity:.7;font-size:12px;" id="__v12_rid">RID: ...</div>' +
            '<button id="__v12_close" title="Disable mini charts" ' +
              'style="cursor:pointer;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:rgba(255,255,255,.9);border-radius:10px;padding:4px 8px;">×</button>' +
          '</div>' +
        '</div>' +
        '<div style="margin-top:8px;opacity:.80;font-size:12px;">Loading /api/vsp/top_findings_v1 ...</div>';

      function mount(){
        try{
          if(!document.body) return false;
          document.body.appendChild(el);
          var b = el.querySelector("#__v12_close");
          if(b){
            b.addEventListener("click", function(){
              try{ localStorage.setItem("vsp_minicharts_off","1"); }catch(e){}
              try{ el.remove(); }catch(e){}
            });
          }
          return true;
        }catch(e){ return false; }
      }

      // wait for body
      var tries=0;
      (function waitBody(){
        tries++;
        if(mount()) { dbg("[V12] mounted"); return; }
        if(tries<40) setTimeout(waitBody, 50);
      })();

      return el;
    }

    function render(el, api){
      var ok = !!(api && api.ok);
      var rid = api && api.rid ? String(api.rid) : "";
      var items = (api && api.items) ? api.items : [];
      if(!Array.isArray(items)) items=[];

      var ridEl = el.querySelector("#__v12_rid");
      if(ridEl) ridEl.textContent = "RID: " + (rid || "(auto)");

      if(!ok){
        el.innerHTML =
          '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;">' +
            '<div style="font-weight:650;">Mini Charts</div>' +
            '<div style="opacity:.7;font-size:12px;">API error</div>' +
          '</div>' +
          '<div style="margin-top:8px;opacity:.80;font-size:12px;">/api/vsp/top_findings_v1?limit=200 failed</div>' +
          '<div style="margin-top:8px;opacity:.70;font-size:12px;">Try: /vsp5?mcdebug=1</div>';
        return;
      }

      var c = compute(items);
      var sev=c.sevCount;
      var maxSev=0;
      ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(function(k){ maxSev=Math.max(maxSev, sev[k]||0); });

      var topToolMax=0;
      for(var i=0;i<c.topTools.length;i++) topToolMax=Math.max(topToolMax, c.topTools[i][1]||0);

      var topCweMax=0;
      for(var j=0;j<c.topCWE.length;j++) topCweMax=Math.max(topCweMax, c.topCWE[j][1]||0);

      var sevHtml =
        barRow("CRITICAL", sev.CRITICAL||0, maxSev) +
        barRow("HIGH",     sev.HIGH||0,     maxSev) +
        barRow("MEDIUM",   sev.MEDIUM||0,   maxSev) +
        barRow("LOW",      sev.LOW||0,      maxSev) +
        barRow("INFO",     sev.INFO||0,     maxSev) +
        barRow("TRACE",    sev.TRACE||0,    maxSev);

      var toolHtml = c.topTools.length ? c.topTools.map(function(x){ return barRow(x[0], x[1], topToolMax); }).join("") :
        '<div style="opacity:.75;font-size:12px;">No CRITICAL/HIGH tools.</div>';

      var cweHtml = c.topCWE.length ? c.topCWE.map(function(x){ return barRow(x[0], x[1], topCweMax); }).join("") :
        '<div style="opacity:.75;font-size:12px;">No CWE field.</div>';

      el.innerHTML =
        '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;">' +
          '<div style="font-weight:650;letter-spacing:.2px;">Mini Charts</div>' +
          '<div style="display:flex;align-items:center;gap:8px;">' +
            '<div style="opacity:.7;font-size:12px;">RID: '+esc(rid||"(auto)")+'</div>' +
            '<button id="__v12_close" title="Disable mini charts" ' +
              'style="cursor:pointer;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:rgba(255,255,255,.9);border-radius:10px;padding:4px 8px;">×</button>' +
          '</div>' +
        '</div>' +
        '<div style="margin-top:8px;opacity:.75;font-size:12px;">sample='+esc(items.length)+' (API-only)</div>' +
        '<div style="margin-top:10px;">' + sevHtml + '</div>' +
        '<div style="margin-top:10px;border-top:1px solid rgba(255,255,255,.10);padding-top:10px;">' +
          '<div style="opacity:.80;font-size:12px;margin-bottom:6px;">Top Tool (CRITICAL/HIGH)</div>' +
          toolHtml +
        '</div>' +
        '<div style="margin-top:10px;border-top:1px solid rgba(255,255,255,.10);padding-top:10px;">' +
          '<div style="opacity:.80;font-size:12px;margin-bottom:6px;">Top CWE</div>' +
          cweHtml +
        '</div>' +
        '<div style="margin-top:10px;opacity:.60;font-size:12px;">Source: /api/vsp/top_findings_v1?limit=200</div>';

      // rebind close
      try{
        var b = el.querySelector("#__v12_close");
        if(b){
          b.addEventListener("click", function(){
            try{ localStorage.setItem("vsp_minicharts_off","1"); }catch(e){}
            try{ el.remove(); }catch(e){}
          });
        }
      }catch(e){}
    }

    async function boot(){
      var el = ensureWidget();
      try{
        var api = await fetchJSON("/api/vsp/top_findings_v1?limit=200", 2500);
        dbg("[V12] api ok=", api && api.ok, "rid=", api && api.rid, "items=", api && (api.items||[]).length);
        render(el, api);
      }catch(e){
        dbg("[V12] fetch error", e);
        render(el, {ok:false});
      }
    }

    // boot after DOM ready
    if(document.readyState === "complete" || document.readyState === "interactive"){
      setTimeout(boot, 120);
    }else{
      document.addEventListener("DOMContentLoaded", function(){ setTimeout(boot, 120); }, {once:true});
    }
  }catch(e){}
})();
'''
s = s + v12 + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended: VSP_P1_DASH_MINICHARTS_V12_FLOATING_WIDGET_API_ONLY_V1")
PY

node --check "$BUNDLE" >/dev/null
echo "[OK] node --check PASS: $BUNDLE"
echo "[DONE] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp5"
echo "[DEBUG] nếu không thấy: mở http://127.0.0.1:8910/vsp5?mcdebug=1"
echo "[FORCE] nếu bạn từng tắt: mở http://127.0.0.1:8910/vsp5?mcforce=1"
