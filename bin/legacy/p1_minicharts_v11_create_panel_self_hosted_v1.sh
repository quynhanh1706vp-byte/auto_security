#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BUNDLE="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE" "${BUNDLE}.bak_v11_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_v11_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove V10 block (and anything after it) if present, then append V11.
m = "/* ===== VSP_P1_DASH_MINICHARTS_V10_CLEAN_API_ONLY_REPLACE_SAFE_PANEL_V1 ====="
i = s.find(m)
if i != -1:
    s = s[:i].rstrip() + "\n\n"
    print("[OK] removed old V10 block at byte", i)

v11 = r'''
/* ===== VSP_P1_DASH_MINICHARTS_V11_SELF_HOSTED_PANEL_API_ONLY_V1 =====
   - Self-hosted panel: creates its own container (no dependency on "Mini Charts (safe)").
   - API-only: /api/vsp/top_findings_v1?limit=200 (NO rid).
   - Very light rendering (bars + small tables), no heavy scans, no observers.
   - Debug: add ?mcdebug=1 to URL (or localStorage.vsp_debug_minicharts=1)
*/
(function(){
  try{
    if(window.__VSP_MINICHARTS_V11_DONE) return;
    window.__VSP_MINICHARTS_V11_DONE = true;

    function isDebug(){
      try{
        if(String(localStorage.getItem("vsp_debug_minicharts")||"") === "1") return true;
      }catch(e){}
      try{
        return (String(location.search||"").indexOf("mcdebug=1") !== -1);
      }catch(e){}
      return false;
    }
    function dbg(){ if(isDebug()) try{ console.log.apply(console, arguments); }catch(e){} }

    // Kill switch
    try{
      if(String(localStorage.getItem("vsp_minicharts_off")||"") === "1"){
        dbg("[V11] disabled by vsp_minicharts_off");
        return;
      }
    }catch(e){}

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

    function ensurePanel(){
      var id = "__vsp_minicharts_v11_panel";
      var el = document.getElementById(id);
      if(el) return el;

      el = document.createElement("div");
      el.id = id;
      el.style.cssText =
        "margin:14px 0; padding:12px 14px;" +
        "border-radius:16px; border:1px solid rgba(255,255,255,.09);" +
        "background:rgba(0,0,0,.18);";

      el.innerHTML =
        '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;">' +
          '<div style="font-weight:650;letter-spacing:.2px;">Mini Charts</div>' +
          '<div style="opacity:.65;font-size:12px;">API-only</div>' +
        '</div>' +
        '<div style="margin-top:8px;opacity:.75;font-size:12px;">Loading /api/vsp/top_findings_v1 ...</div>';

      // Insert position: try after "Top Findings" table; else append near end of dashboard content.
      var inserted = false;

      // Heuristic: find first table that looks like top findings (headers include Severity/Title/Tool)
      try{
        var tables = Array.from(document.querySelectorAll("table"));
        var target = null;
        for(var i=0;i<tables.length;i++){
          var t = tables[i];
          var txt = (t.innerText||"").toLowerCase();
          if(txt.includes("severity") && txt.includes("title") && txt.includes("tool")){
            target = t;
            break;
          }
        }
        if(target && target.parentElement){
          // insert after the table container
          var box = target;
          for(var k=0;k<6 && box && box.parentElement;k++){
            var r = box.getBoundingClientRect ? box.getBoundingClientRect() : null;
            if(r && r.width >= 520) break;
            box = box.parentElement;
          }
          (box.parentElement || target.parentElement).insertBefore(el, (box.nextSibling || null));
          inserted = true;
        }
      }catch(e){}

      if(!inserted){
        try{
          // fallback: insert before bottom nav tabs if exists
          var nav = document.querySelector("button, a");
          var candidates = Array.from(document.querySelectorAll("button,a")).filter(function(x){
            return (x.textContent||"").trim().toLowerCase() === "dashboard";
          });
          if(candidates.length){
            var host = candidates[0];
            for(var j=0;j<10 && host && host.parentElement;j++){
              var r2 = host.getBoundingClientRect ? host.getBoundingClientRect() : null;
              if(r2 && r2.width >= 520) break;
              host = host.parentElement;
            }
            (host.parentElement || document.body).insertBefore(el, host);
            inserted = true;
          }
        }catch(e){}
      }

      if(!inserted){
        try{ document.body.appendChild(el); inserted = true; }catch(e){}
      }

      dbg("[V11] panel inserted=", inserted);
      return el;
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
      var topTools = Object.entries(toolCH).sort(function(a,b){ return (b[1]||0)-(a[1]||0); }).slice(0,8);
      var topCWE = Object.entries(cweCount).sort(function(a,b){ return (b[1]||0)-(a[1]||0); }).slice(0,8);
      return { sevCount: sevCount, topTools: topTools, topCWE: topCWE };
    }

    function render(panel, api){
      var ok = !!(api && api.ok);
      var rid = api && api.rid ? String(api.rid) : "";
      var items = (api && api.items) ? api.items : [];
      if(!Array.isArray(items)) items = [];

      var header =
        '<div style="display:flex;align-items:center;justify-content:space-between;gap:10px;">' +
          '<div style="font-weight:650;letter-spacing:.2px;">Mini Charts</div>' +
          '<div style="opacity:.75;font-size:12px;white-space:nowrap;">RID: '+(rid?esc(rid):'(auto)')+'</div>' +
        '</div>';

      if(!ok){
        panel.innerHTML =
          '<div>'+header+'</div>' +
          '<div style="margin-top:10px;opacity:.85;font-size:12px;">API error: /api/vsp/top_findings_v1?limit=200</div>' +
          '<div style="margin-top:6px;opacity:.70;font-size:12px;">Tip: thêm <b>?mcdebug=1</b> vào URL để log.</div>';
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

      var foot =
        '<div style="margin-top:10px;opacity:.65;font-size:12px;">Source: /api/vsp/top_findings_v1?limit=200 (no rid)</div>';

      panel.innerHTML = header + grid + foot;
    }

    async function boot(){
      var panel = ensurePanel();
      try{
        var api = await fetchJSON("/api/vsp/top_findings_v1?limit=200", 2500);
        dbg("[V11] api ok=", api && api.ok, "rid=", api && api.rid, "items=", api && (api.items||[]).length);
        render(panel, api);
      }catch(e){
        dbg("[V11] fetch error", e);
        render(panel, { ok:false });
      }
    }

    setTimeout(boot, 260);
  }catch(e){}
})();
'''
s = s + v11 + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended: VSP_P1_DASH_MINICHARTS_V11_SELF_HOSTED_PANEL_API_ONLY_V1")
PY

node --check "$BUNDLE" >/dev/null
echo "[OK] node --check PASS: $BUNDLE"
echo "[DONE] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp5"
echo "[DEBUG] nếu muốn xem log: mở http://127.0.0.1:8910/vsp5?mcdebug=1"
