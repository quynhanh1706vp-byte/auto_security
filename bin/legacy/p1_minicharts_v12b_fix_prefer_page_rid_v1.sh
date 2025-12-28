#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BUNDLE="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$BUNDLE" "${BUNDLE}.bak_v12b_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_v12b_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker_old = "VSP_P1_DASH_MINICHARTS_V12_FLOATING_WIDGET_API_ONLY_V1"
marker_new = "VSP_P1_DASH_MINICHARTS_V12B_PREFER_PAGE_RID_V1"

# truncate from old V12 marker if present (keep everything before it)
idx = s.find(f"/* ===== {marker_old} =====")
if idx >= 0:
    s = s[:idx].rstrip() + "\n"

# also truncate from any earlier V12B marker (idempotent)
idx2 = s.find(f"/* ===== {marker_new} =====")
if idx2 >= 0:
    s = s[:idx2].rstrip() + "\n"

append = r"""
/* ===== VSP_P1_DASH_MINICHARTS_V12B_PREFER_PAGE_RID_V1 ===== */
(function(){
  try{
    var qs = new URLSearchParams(location.search || "");
    var mcdebug = qs.get("mcdebug") === "1";
    var mcforce = qs.get("mcforce") === "1";

    try{
      if(mcforce){
        try{ localStorage.removeItem("vsp_minicharts_off"); }catch(e){}
      }
      if(!mcforce){
        try{
          if(localStorage.getItem("vsp_minicharts_off") === "1"){ return; }
        }catch(e){}
      }
    }catch(e){}

    function log(){
      if(!mcdebug) return;
      try{ console.log.apply(console, ["[minicharts_v12b]"].concat([].slice.call(arguments))); }catch(e){}
    }

    function getPageRid(){
      try{
        var rid = (new URLSearchParams(location.search||"")).get("rid") || "";
        rid = String(rid||"").trim();
        if(!rid) return "";
        if(rid === "YOUR_RID") return "";
        if(rid.toLowerCase() === "null" || rid.toLowerCase() === "undefined") return "";
        return rid;
      }catch(e){ return ""; }
    }

    function safeText(x){ return (x==null) ? "" : String(x); }

    function buildPanel(){
      var panel = document.getElementById("__vsp_minicharts_v12b");
      if(panel) return panel;

      panel = document.createElement("div");
      panel.id="__vsp_minicharts_v12b";
      panel.style.position="fixed";
      panel.style.right="16px";
      panel.style.bottom="16px";
      panel.style.width="360px";
      panel.style.maxWidth="calc(100vw - 32px)";
      panel.style.zIndex="99999";
      panel.style.border="1px solid rgba(255,255,255,0.08)";
      panel.style.borderRadius="12px";
      panel.style.background="rgba(10,14,22,0.92)";
      panel.style.backdropFilter="blur(8px)";
      panel.style.boxShadow="0 10px 30px rgba(0,0,0,0.45)";
      panel.style.color="rgba(255,255,255,0.86)";
      panel.style.fontFamily="ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif";
      panel.style.fontSize="12px";
      panel.style.overflow="hidden";

      var head = document.createElement("div");
      head.style.display="flex";
      head.style.alignItems="center";
      head.style.justifyContent="space-between";
      head.style.padding="10px 10px 8px 10px";
      head.style.borderBottom="1px solid rgba(255,255,255,0.06)";

      var title = document.createElement("div");
      title.innerHTML = '<div style="font-weight:700; letter-spacing:0.2px">Mini Charts</div>'
                      + '<div id="__vsp_minicharts_v12b_meta" style="margin-top:2px; opacity:0.75; font-size:11px">loading…</div>';

      var btn = document.createElement("button");
      btn.textContent="×";
      btn.title="Hide (persist)";
      btn.style.border="1px solid rgba(255,255,255,0.10)";
      btn.style.background="rgba(255,255,255,0.04)";
      btn.style.color="rgba(255,255,255,0.85)";
      btn.style.borderRadius="10px";
      btn.style.width="34px";
      btn.style.height="26px";
      btn.style.cursor="pointer";
      btn.onclick=function(){
        try{ localStorage.setItem("vsp_minicharts_off","1"); }catch(e){}
        try{ panel.remove(); }catch(e){}
      };

      head.appendChild(title);
      head.appendChild(btn);

      var body = document.createElement("div");
      body.id="__vsp_minicharts_v12b_body";
      body.style.padding="10px";
      body.style.maxHeight="40vh";
      body.style.overflow="auto";

      panel.appendChild(head);
      panel.appendChild(body);

      try{ document.body.appendChild(panel); }catch(e){}
      return panel;
    }

    function barRow(label, val, total){
      var pct = (total>0) ? Math.round((val*1000)/total)/10 : 0; // 1 decimal
      var row = document.createElement("div");
      row.style.display="grid";
      row.style.gridTemplateColumns="90px 1fr 52px";
      row.style.gap="8px";
      row.style.alignItems="center";
      row.style.margin="6px 0";

      var l = document.createElement("div");
      l.textContent = label;
      l.style.opacity="0.85";

      var track = document.createElement("div");
      track.style.height="10px";
      track.style.borderRadius="999px";
      track.style.background="rgba(255,255,255,0.08)";
      track.style.overflow="hidden";

      var fill = document.createElement("div");
      fill.style.height="100%";
      fill.style.width = Math.max(0, Math.min(100, pct)) + "%";
      fill.style.background="rgba(130,190,255,0.75)";
      track.appendChild(fill);

      var r = document.createElement("div");
      r.style.textAlign="right";
      r.style.opacity="0.82";
      r.textContent = val + " (" + pct + "%)";

      row.appendChild(l); row.appendChild(track); row.appendChild(r);
      return row;
    }

    function renderFromItems(items, pageRid, apiRid){
      var panel = buildPanel();
      var meta = panel.querySelector("#__vsp_minicharts_v12b_meta");
      var body = panel.querySelector("#__vsp_minicharts_v12b_body");
      if(meta) meta.textContent = "RID(page)=" + (pageRid||"(none)") + " • RID(api)=" + (apiRid||"(none)") + " • n=" + (items?items.length:0);

      if(!body) return;
      body.innerHTML = "";

      var total = items.length || 0;
      if(total <= 0){
        body.textContent = "No data (items=0).";
        return;
      }

      var sevOrder = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      var sevCount = {};
      for(var i=0;i<sevOrder.length;i++) sevCount[sevOrder[i]]=0;

      var toolCount = {}; // only HIGH/CRITICAL
      for(var k=0;k<items.length;k++){
        var it = items[k] || {};
        var sev = safeText(it.severity).toUpperCase().trim();
        if(!sev) continue;
        if(sevCount.hasOwnProperty(sev)) sevCount[sev] += 1;

        if(sev === "CRITICAL" || sev === "HIGH"){
          var t = safeText(it.tool).toLowerCase().trim() || "unknown";
          toolCount[t] = (toolCount[t]||0) + 1;
        }
      }

      var h = document.createElement("div");
      h.textContent = "Severity Distribution";
      h.style.fontWeight="700";
      h.style.margin="2px 0 8px 0";
      body.appendChild(h);

      for(var j=0;j<sevOrder.length;j++){
        var sname = sevOrder[j];
        var v = sevCount[sname] || 0;
        body.appendChild(barRow(sname, v, total));
      }

      var h2 = document.createElement("div");
      h2.textContent = "Critical/High by Tool";
      h2.style.fontWeight="700";
      h2.style.margin="12px 0 6px 0";
      body.appendChild(h2);

      var entries = Object.entries(toolCount).sort(function(a,b){ return (b[1]||0) - (a[1]||0); }).slice(0,10);
      if(entries.length === 0){
        var em = document.createElement("div");
        em.textContent = "(none)";
        em.style.opacity="0.75";
        body.appendChild(em);
      }else{
        var sum = entries.reduce(function(acc,x){ return acc + (x[1]||0); }, 0);
        for(var z=0; z<entries.length; z++){
          body.appendChild(barRow(entries[z][0], entries[z][1]||0, sum));
        }
      }
    }

    async function run(){
      var pageRid = getPageRid();
      var url = "/api/vsp/top_findings_v1?limit=200";
      if(pageRid){
        url += "&rid=" + encodeURIComponent(pageRid);
      }

      var panel = buildPanel();
      var meta = panel.querySelector("#__vsp_minicharts_v12b_meta");
      var body = panel.querySelector("#__vsp_minicharts_v12b_body");
      if(meta) meta.textContent = "loading… " + url;
      if(body) body.textContent = "Loading…";

      try{
        var res = await fetch(url, {credentials:"same-origin", cache:"no-store"});
        if(!res.ok){
          if(body) body.textContent = "HTTP " + res.status + " for " + url;
          log("http_fail", res.status, url);
          return;
        }
        var j = await res.json();
        var items = (j && j.items) ? j.items : [];
        var apiRid = (j && j.rid) ? String(j.rid) : "";
        log("ok", "pageRid=", pageRid, "apiRid=", apiRid, "items=", items.length);
        renderFromItems(items, pageRid, apiRid);
      }catch(e){
        if(body) body.textContent = "Fetch/parse error: " + (e && e.message ? e.message : String(e));
        log("err", e);
      }
    }

    setTimeout(run, 450);
  }catch(e){}
})();
"""

s = s.rstrip() + "\n\n" + append + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended:", marker_new)
PY

node --check "$BUNDLE" >/dev/null
echo "[OK] node --check PASS: $BUNDLE"
echo "[DONE] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp5?rid=VSP_CI_20251218_114312"
echo "[DEBUG] nếu muốn log: http://127.0.0.1:8910/vsp5?rid=VSP_CI_20251218_114312&mcdebug=1"
