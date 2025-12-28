#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_minicharts_v8_${TS}"
echo "[BACKUP] ${JS}.bak_minicharts_v8_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASH_MINICHARTS_V8_API_NORID_FAST_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

addon = r"""
/* ===== VSP_P1_DASH_MINICHARTS_V8_API_NORID_FAST_V1 =====
   - Always uses /api/vsp/top_findings_v1?limit=N (NO rid needed; server picks rid)
   - Renders fast bars (no loops/observers)
   - Also scrubs ?rid=YOUR_RID from location to avoid poisoning UI
*/
(function(){
  try{
    if(window.__VSP_MINICHARTS_V8_DONE) return;
    window.__VSP_MINICHARTS_V8_DONE = true;

    // scrub rid=YOUR_RID from URL
    try{
      var uu = new URL(location.href);
      var r0 = (uu.searchParams.get("rid") || uu.searchParams.get("RID") || "").toString().trim();
      if(r0 === "YOUR_RID"){
        uu.searchParams.delete("rid"); uu.searchParams.delete("RID");
        history.replaceState(null, "", uu.toString());
      }
    }catch(e){}

    function esc(x){
      x = (x==null?"":String(x));
      return x.replace(/[&<>"]/g, function(c){
        return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c] || c);
      });
    }

    function findHeaderExact(txt){
      var nodes = document.querySelectorAll("h1,h2,h3,h4,div,span");
      txt = (txt||"").trim();
      for(var i=0;i<nodes.length;i++){
        var t = (nodes[i].textContent||"").trim();
        if(t === txt) return nodes[i];
      }
      return null;
    }

    function insertPanelAfter(anchorEl, panel){
      try{
        var host = anchorEl.closest("div");
        if(!host || !host.parentNode) return false;
        host.parentNode.insertBefore(panel, host.nextSibling);
        return true;
      }catch(e){}
      return false;
    }

    function mkPanel(){
      var d = document.createElement("div");
      d.style.marginTop = "10px";
      d.style.padding = "12px";
      d.style.border = "1px solid rgba(255,255,255,0.08)";
      d.style.borderRadius = "12px";
      d.style.background = "rgba(255,255,255,0.02)";
      d.style.backdropFilter = "blur(2px)";
      d.innerHTML = '<div style="font-weight:700;opacity:.9">Mini Charts (safe v8)</div>' +
                    '<div style="opacity:.75;font-size:12px;margin-top:4px">Source: /api/vsp/top_findings_v1 (no rid)</div>' +
                    '<div class="__v8_body" style="margin-top:8px;opacity:.85;font-size:12px">Loading…</div>';
      return d;
    }

    function barRow(label, val, max){
      val = Number(val||0); max = Number(max||0);
      var pct = (max>0) ? Math.max(0, Math.min(100, Math.round(val*100/max))) : 0;
      return (
        '<div style="display:flex;gap:10px;align-items:center;margin:6px 0">' +
          '<div style="width:110px;opacity:.85">' + esc(label) + '</div>' +
          '<div style="flex:1;height:10px;border-radius:999px;background:rgba(255,255,255,0.06);overflow:hidden">' +
            '<div style="height:10px;width:'+pct+'%;background:rgba(255,255,255,0.22)"></div>' +
          '</div>' +
          '<div style="width:44px;text-align:right;opacity:.9">' + esc(val) + '</div>' +
        '</div>'
      );
    }

    async function run(){
      var panel = mkPanel();

      // anchor: prefer "By Tool Buckets" section; else append to body bottom
      var anchor = findHeaderExact("By Tool Buckets") || findHeaderExact("Top Risk Findings") || findHeaderExact("Top CWE Exposure");
      if(anchor){
        insertPanelAfter(anchor, panel);
      }else{
        try{ document.body.appendChild(panel); }catch(e){}
      }

      var body = panel.querySelector(".__v8_body");
      if(!body) return;

      var N = 800; // safe cap
      var url = "/api/vsp/top_findings_v1?limit=" + N;
      var j = null;
      try{
        var r = await fetch(url, { credentials: "same-origin" });
        j = await r.json();
      }catch(e){}
      if(!j || !j.ok){
        body.textContent = "No data (degraded) — API failed: " + url;
        return;
      }

      var items = Array.isArray(j.items) ? j.items : [];
      var rid = (j.rid || j.RID || "").toString().trim();
      var sevCount = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      var toolCount = {};
      var cweCount = {};

      for(var i=0;i<items.length;i++){
        var it = items[i] || {};
        var sev = (it.severity || it.SEVERITY || "").toString().trim().toUpperCase();
        if(sevCount.hasOwnProperty(sev)) sevCount[sev]++; else if(sev) { /* ignore unknown */ }
        var tool = (it.tool || it.TOOL || "").toString().trim();
        if(tool){
          toolCount[tool] = (toolCount[tool]||0) + 1;
        }
        var cwe = (it.cwe || it.CWE || "").toString().trim();
        if(cwe){
          cweCount[cwe] = (cweCount[cwe]||0) + 1;
        }
      }

      var maxSev = 0;
      Object.keys(sevCount).forEach(function(k){ if(sevCount[k] > maxSev) maxSev = sevCount[k]; });

      var toolPairs = Object.entries(toolCount).sort(function(a,b){ return (b[1]-a[1]); }).slice(0,6);
      var maxTool = toolPairs.length ? toolPairs[0][1] : 0;

      var cwePairs = Object.entries(cweCount).sort(function(a,b){ return (b[1]-a[1]); }).slice(0,6);
      var maxCwe = cwePairs.length ? cwePairs[0][1] : 0;

      var html = "";
      html += '<div style="opacity:.9;margin-bottom:8px">RID: <b>'+esc(rid||"(server-default)")+'</b> · items(sample): <b>'+esc(items.length)+'</b></div>';

      html += '<div style="font-weight:700;opacity:.85;margin:8px 0 4px">Severity Distribution</div>';
      ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(function(k){
        html += barRow(k, sevCount[k]||0, maxSev);
      });

      html += '<div style="font-weight:700;opacity:.85;margin:10px 0 4px">Top Tools</div>';
      if(toolPairs.length){
        toolPairs.forEach(function(p){
          html += barRow(p[0], p[1], maxTool);
        });
      }else{
        html += '<div style="opacity:.75">No tool field in items.</div>';
      }

      html += '<div style="font-weight:700;opacity:.85;margin:10px 0 4px">Top CWE</div>';
      if(cwePairs.length){
        cwePairs.forEach(function(p){
          html += barRow(p[0], p[1], maxCwe);
        });
      }else{
        html += '<div style="opacity:.75">No CWE field in items.</div>';
      }

      body.innerHTML = html;
    }

    // run once after page settles
    setTimeout(function(){ run().catch(function(){}); }, 350);
  }catch(e){}
})();
""".strip()

p.write_text(s.rstrip() + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended:", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS"; exit 2; }

echo "[DONE] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp5 (KHÔNG dùng ?rid=YOUR_RID)"
