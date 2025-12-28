#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_minicharts_v8b_${TS}"
echo "[BACKUP] ${JS}.bak_minicharts_v8b_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASH_MINICHARTS_V8B_KILLSWITCH_PIN_V1"
if marker in s:
    print("[OK] already patched:", marker)
    raise SystemExit(0)

addon = r"""
/* ===== VSP_P1_DASH_MINICHARTS_V8B_KILLSWITCH_PIN_V1 =====
   Goal:
   - Kill legacy "Mini Charts (safe)" degraded block (hide it) to avoid confusion/freeze
   - Force-render a new panel right there using /api/vsp/top_findings_v1?limit=N (NO rid)
   - Scrub ?rid=YOUR_RID in URL + fix footer RID display if poisoned
*/
(function(){
  try{
    if(window.__VSP_MINICHARTS_V8B_DONE) return;
    window.__VSP_MINICHARTS_V8B_DONE = true;

    function esc(x){
      x = (x==null?"":String(x));
      return x.replace(/[&<>"]/g, function(c){
        return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c] || c);
      });
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

    // scrub rid=YOUR_RID from URL
    try{
      var uu = new URL(location.href);
      var r0 = (uu.searchParams.get("rid") || uu.searchParams.get("RID") || "").toString().trim();
      if(r0 === "YOUR_RID"){
        uu.searchParams.delete("rid"); uu.searchParams.delete("RID");
        history.replaceState(null, "", uu.toString());
      }
    }catch(e){}

    function findMiniChartsSafeAnchor(){
      // Find the existing "Mini Charts (safe)" header on page with a small capped scan
      var divs = document.querySelectorAll("div,span,h1,h2,h3,h4");
      var cap = Math.min(divs.length, 1800);
      for(var i=0;i<cap;i++){
        var t = (divs[i].textContent || "").trim();
        if(!t) continue;
        if(t === "Mini Charts (safe)" || t.indexOf("Mini Charts (safe)") >= 0){
          return divs[i];
        }
      }
      return null;
    }

    function hideLegacyBlock(anchorEl){
      // Hide a reasonable container around the old block (avoid expensive DOM walks)
      try{
        var host = anchorEl.closest("div");
        if(host){
          host.style.display = "none";
          host.style.visibility = "hidden";
          host.style.height = "0px";
          host.style.margin = "0px";
          host.style.padding = "0px";
        }
      }catch(e){}
    }

    function mkPanel(){
      var d = document.createElement("div");
      d.style.marginTop = "10px";
      d.style.padding = "12px";
      d.style.border = "1px solid rgba(255,255,255,0.10)";
      d.style.borderRadius = "12px";
      d.style.background = "rgba(255,255,255,0.025)";
      d.style.backdropFilter = "blur(2px)";
      d.innerHTML =
        '<div style="font-weight:800;opacity:.92">Mini Charts (safe v8b)</div>' +
        '<div style="opacity:.75;font-size:12px;margin-top:4px">Source: /api/vsp/top_findings_v1 (no rid)</div>' +
        '<div class="__v8b_body" style="margin-top:10px;opacity:.88;font-size:12px">Loading…</div>';
      return d;
    }

    function tryFixFooterRID(realRid){
      // Replace visible "RID: YOUR_RID" text if present (best-effort, capped)
      try{
        var nodes = document.querySelectorAll("div,span");
        var cap = Math.min(nodes.length, 1400);
        for(var i=0;i<cap;i++){
          var t = (nodes[i].textContent || "");
          if(t.indexOf("RID:") >= 0 && t.indexOf("YOUR_RID") >= 0){
            nodes[i].textContent = t.replace("YOUR_RID", realRid || "(server-default)");
            return;
          }
        }
      }catch(e){}
    }

    async function renderInto(panelBody){
      var url = "/api/vsp/top_findings_v1?limit=900";
      var j = null;
      try{
        var r = await fetch(url, { credentials: "same-origin" });
        j = await r.json();
      }catch(e){}
      if(!j || !j.ok){
        panelBody.textContent = "No data (degraded) — API failed: " + url;
        return;
      }
      var items = Array.isArray(j.items) ? j.items : [];
      var rid = (j.rid || j.RID || "").toString().trim() || "(server-default)";

      var sevCount = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      var toolCount = {};
      var cweCount = {};

      for(var i=0;i<items.length;i++){
        var it = items[i] || {};
        var sev = (it.severity || it.SEVERITY || "").toString().trim().toUpperCase();
        if(sevCount.hasOwnProperty(sev)) sevCount[sev]++;

        var tool = (it.tool || it.TOOL || "").toString().trim();
        if(tool) toolCount[tool] = (toolCount[tool]||0) + 1;

        var cwe = (it.cwe || it.CWE || "").toString().trim();
        if(cwe) cweCount[cwe] = (cweCount[cwe]||0) + 1;
      }

      var maxSev = 0;
      Object.keys(sevCount).forEach(function(k){ if(sevCount[k] > maxSev) maxSev = sevCount[k]; });

      var toolPairs = Object.entries(toolCount).sort(function(a,b){ return b[1]-a[1]; }).slice(0,6);
      var maxTool = toolPairs.length ? toolPairs[0][1] : 0;

      var cwePairs = Object.entries(cweCount).sort(function(a,b){ return b[1]-a[1]; }).slice(0,6);
      var maxCwe = cwePairs.length ? cwePairs[0][1] : 0;

      var html = '';
      html += '<div style="opacity:.92;margin-bottom:10px">RID: <b>'+esc(rid)+'</b> · items(sample): <b>'+esc(items.length)+'</b></div>';

      html += '<div style="font-weight:800;opacity:.85;margin:8px 0 4px">Severity</div>';
      ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(function(k){
        html += barRow(k, sevCount[k]||0, maxSev);
      });

      html += '<div style="font-weight:800;opacity:.85;margin:12px 0 4px">Top Tools</div>';
      if(toolPairs.length){
        toolPairs.forEach(function(p){ html += barRow(p[0], p[1], maxTool); });
      }else{
        html += '<div style="opacity:.75">No tool field in items.</div>';
      }

      html += '<div style="font-weight:800;opacity:.85;margin:12px 0 4px">Top CWE</div>';
      if(cwePairs.length){
        cwePairs.forEach(function(p){ html += barRow(p[0], p[1], maxCwe); });
      }else{
        html += '<div style="opacity:.75">No CWE field in items.</div>';
      }

      panelBody.innerHTML = html;
      tryFixFooterRID(rid);
    }

    function boot(){
      // 1) locate legacy mini charts safe block and hide it
      var anchor = findMiniChartsSafeAnchor();
      if(anchor) hideLegacyBlock(anchor);

      // 2) insert our panel near the legacy area (or near By Tool Buckets if found)
      var panel = mkPanel();
      var inserted = false;

      try{
        if(anchor){
          var host = anchor.closest("div");
          if(host && host.parentNode){
            host.parentNode.insertBefore(panel, host.nextSibling);
            inserted = true;
          }
        }
      }catch(e){}

      if(!inserted){
        // fallback: append to end of body
        try{ document.body.appendChild(panel); }catch(e){}
      }

      var body = panel.querySelector(".__v8b_body");
      if(body) renderInto(body).catch(function(){});
    }

    // run once after initial layout
    setTimeout(boot, 450);
  }catch(e){}
})();
""".strip()

p.write_text(s.rstrip() + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended:", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS"; exit 2; }

echo "[DONE] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp5  (đừng dùng ?rid=YOUR_RID)"
