#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BUNDLE="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE" "${BUNDLE}.bak_v10clean_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_v10clean_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Trim all legacy minicharts blocks appended before (to prevent freezes / conflicts)
marker = "/* ===== VSP_P1_DASH_MINICHARTS_"
idx = s.find(marker)
if idx != -1:
    s = s[:idx].rstrip() + "\n\n"
    print("[OK] trimmed legacy minicharts from first marker at byte", idx)
else:
    print("[OK] no legacy minicharts marker found; will just append V10")

# 2) Append ONE safe V10 block (API-only, no rid required)
v10 = r'''
/* ===== VSP_P1_DASH_MINICHARTS_V10_CLEAN_API_ONLY_REPLACE_SAFE_PANEL_V1 =====
   - Remove legacy minicharts by trimming file from first minicharts marker.
   - Render lightweight bars using /api/vsp/top_findings_v1?limit=200 (NO rid).
   - Replace the existing "Mini Charts (safe)" panel content (so user sees it immediately).
   - No heavy DOM scan, no MutationObserver, no infinite loops.
*/
(function(){
  try{
    if(window.__VSP_MINICHARTS_V10_DONE) return;
    window.__VSP_MINICHARTS_V10_DONE = true;

    function dbg(){
      try{
        if(String(localStorage.getItem("vsp_debug_minicharts")||"") === "1"){
          console.log.apply(console, arguments);
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

    function xfirst(expr){
      try{
        return document.evaluate(expr, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
      }catch(e){ return null; }
    }

    function findSafePanelHost(){
      // Prefer the "Mini Charts (safe)" section (has "Mini Charts" + "Source:" text)
      var node =
        xfirst("//*[contains(translate(.,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'mini charts') and contains(.,'Source')]")
        || xfirst("//*[contains(translate(.,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'),'mini charts')]");
      if(!node) return null;

      // Climb to a reasonable container
      var host = node;
      for(var i=0;i<8 && host && host.parentElement;i++){
        var r = host.getBoundingClientRect ? host.getBoundingClientRect() : null;
        if(r && r.width >= 520 && r.height >= 80) break;
        host = host.parentElement;
      }
      return host || node;
    }

    function setPanelHTML(host, html){
      if(!host) return false;
      host.innerHTML = html;
      return true;
    }

    function barRow(label, val, maxVal){
      val = Number(val||0);
      maxVal = Number(maxVal||0);
      var pct = maxVal>0 ? Math.max(0, Math.min(100, Math.round((val/maxVal)*100))) : 0;
      return (
        '<div style="display:flex;align-items:center;gap:10px;margin:6px 0;">' +
          '<div style="width:92px;opacity:.85;font-size:12px;letter-spacing:.2px;">'+esc(label)+'</div>' +
          '<div style="flex:1;height:10px;background:rgba(255,255,255,.08);border-radius:999px;overflow:hidden;">' +
            '<div style="height:10px;width:'+pct+'%;background:rgba(255,255,255,.30);border-radius:999px;"></div>' +
          '</div>' +
          '<div style="width:54px;text-align:right;opacity:.9;font-size:12px;font-variant-numeric:tabular-nums;">'+esc(val)+'</div>' +
        '</div>'
      );
    }

    function miniCard(title, bodyHtml){
      return (
        '<div style="background:rgba(0,0,0,.18);border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:10px 12px;">' +
          '<div style="opacity:.85;font-size:12px;margin-bottom:8px;letter-spacing:.2px;">'+esc(title)+'</div>' +
          bodyHtml +
        '</div>'
      );
    }

    async function fetchJSON(url, ms){
      var ctl = null;
      try{ ctl = new AbortController(); }catch(e){ ctl = null; }
      var t = null;
      try{
        if(ctl){
          t = setTimeout(function(){ try{ ctl.abort(); }catch(e){} }, ms||2500);
        }
        var res = await fetch(url, { cache:"no-store", signal: ctl ? ctl.signal : undefined });
        var j = await res.json();
        return j;
      } finally {
        if(t) clearTimeout(t);
      }
    }

    function compute(items){
      var sevCount = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      var toolCH = {};
      var cweCount = {};
      var n = items.length;

      for(var i=0;i<n;i++){
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

      var topTools = Object.entries(toolCH).sort(function(a,b){ return (b[1]||0)-(a[1]||0); }).slice(0,8);
      var topCWE = Object.entries(cweCount).sort(function(a,b){ return (b[1]||0)-(a[1]||0); }).slice(0,8);
      return { sevCount: sevCount, topTools: topTools, topCWE: topCWE };
    }

    function render(host, api){
      var ok = !!(api && api.ok);
      var rid = api && (api.rid || api.run_id || api.latest_rid) ? String(api.rid || api.run_id || api.latest_rid) : "";
      var items = (api && api.items) ? api.items : [];
      if(!Array.isArray(items)) items = [];

      var metaRight = rid ? ('RID: '+esc(rid)) : 'RID: (auto)';
      var header =
        '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;">' +
          '<div style="font-weight:650;letter-spacing:.2px;">Mini Charts (API-only)</div>' +
          '<div style="opacity:.75;font-size:12px;white-space:nowrap;">'+metaRight+'</div>' +
        '</div>';

      if(!ok){
        setPanelHTML(host,
          '<div style="padding:12px 14px;">'+header+
          '<div style="margin-top:10px;opacity:.85;font-size:12px;">API error: /api/vsp/top_findings_v1</div>'+
          '<div style="margin-top:6px;opacity:.7;font-size:12px;">Tip: mở Console với localStorage.vsp_debug_minicharts=1 để xem log.</div>'+
          '</div>'
        );
        return;
      }

      var c = compute(items);
      var sev = c.sevCount;
      var maxSev = 0;
      ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(function(k){ maxSev = Math.max(maxSev, sev[k]||0); });

      var sevBody = ""
        + barRow("CRITICAL", sev.CRITICAL||0, maxSev)
        + barRow("HIGH",     sev.HIGH||0,     maxSev)
        + barRow("MEDIUM",   sev.MEDIUM||0,   maxSev)
        + barRow("LOW",      sev.LOW||0,      maxSev)
        + barRow("INFO",     sev.INFO||0,     maxSev)
        + barRow("TRACE",    sev.TRACE||0,    maxSev);

      var toolMax = 0;
      for(var i=0;i<c.topTools.length;i++){ toolMax = Math.max(toolMax, c.topTools[i][1]||0); }
      var toolBody = "";
      if(c.topTools.length){
        for(var j=0;j<c.topTools.length;j++){
          toolBody += barRow(c.topTools[j][0], c.topTools[j][1], toolMax);
        }
      }else{
        toolBody = '<div style="opacity:.75;font-size:12px;">No CRITICAL/HIGH tool buckets.</div>';
      }

      var cweMax = 0;
      for(var k=0;k<c.topCWE.length;k++){ cweMax = Math.max(cweMax, c.topCWE[k][1]||0); }
      var cweBody = "";
      if(c.topCWE.length){
        for(var m=0;m<c.topCWE.length;m++){
          cweBody += barRow(c.topCWE[m][0], c.topCWE[m][1], cweMax);
        }
      }else{
        cweBody = '<div style="opacity:.75;font-size:12px;">No CWE field in items.</div>';
      }

      var grid =
        '<div style="margin-top:10px;display:grid;grid-template-columns:1fr 1fr;gap:12px;">' +
          miniCard("Severity (sample="+esc(items.length)+")", sevBody) +
          miniCard("Top Tool (CRITICAL/HIGH)", toolBody) +
        '</div>' +
        '<div style="margin-top:12px;">' +
          miniCard("Top CWE (if present)", cweBody) +
        '</div>';

      var foot = '<div style="margin-top:10px;opacity:.65;font-size:12px;">Source: /api/vsp/top_findings_v1?limit=200 (no rid)</div>';

      setPanelHTML(host, '<div style="padding:12px 14px;">'+header+grid+foot+'</div>');
    }

    async function boot(){
      var host = findSafePanelHost();
      if(!host){
        dbg("[V10] host not found");
        return;
      }

      // lightweight loading
      setPanelHTML(host,
        '<div style="padding:12px 14px;">' +
          '<div style="font-weight:650;letter-spacing:.2px;">Mini Charts (API-only)</div>' +
          '<div style="margin-top:8px;opacity:.75;font-size:12px;">Loading from /api/vsp/top_findings_v1 ...</div>' +
        '</div>'
      );

      try{
        var api = await fetchJSON('/api/vsp/top_findings_v1?limit=200', 2500);
        dbg("[V10] api ok=", api && api.ok, "rid=", api && api.rid, "items=", api && (api.items||[]).length);
        render(host, api);
      }catch(e){
        dbg("[V10] fetch error", e);
        render(host, { ok:false });
      }
    }

    setTimeout(boot, 260);
  }catch(e){}
})();
'''
s = s + v10 + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended: VSP_P1_DASH_MINICHARTS_V10_CLEAN_API_ONLY_REPLACE_SAFE_PANEL_V1")
PY

node --check "$BUNDLE" >/dev/null
echo "[OK] node --check PASS: $BUNDLE"
echo "[DONE] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp5  (không dùng ?rid=YOUR_RID)"
echo "[TIP] Debug (nếu cần): localStorage.vsp_debug_minicharts=1 rồi refresh."
