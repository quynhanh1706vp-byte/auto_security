#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_v7only_${TS}"
echo "[BACKUP] ${JS}.bak_v7only_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_MINICHARTS_V7_ONLY_SAFE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 0) Put global flag early (top) to let us short-circuit legacy minicharts blocks
flag = "\n;window.__VSP_MINI_V7_ONLY = true;\n"
if "window.__VSP_MINI_V7_ONLY" not in s[:1200]:
    # insert after first newline (keep shebang-less js intact)
    i = s.find("\n")
    if i >= 0:
        s = s[:i+1] + flag + s[i+1:]
    else:
        s = flag + s

# 1) Disable all legacy minicharts blocks by injecting a guard inside their IIFE body.
# We target any block marker that starts with VSP_P1_DASH_MINICHARTS_
# and then find the next IIFE opener and inject: if(window.__VSP_MINI_V7_ONLY) return;
def inject_guard_after_iife_body(src: str, marker_pos: int) -> str:
    # search forward a limited window for function body
    win = src[marker_pos:marker_pos+3000]
    # find likely IIFE start
    m = re.search(r'(\(\s*function\s*\(\)\s*\{|\(\s*\(\)\s*=>\s*\{|\(\s*async\s*function\s*\(\)\s*\{|\(\s*async\s*\(\)\s*=>\s*\{)', win)
    if not m:
        return src
    # absolute index of the "{" in that opener
    abs_start = marker_pos + m.start()
    brace = src.find("{", abs_start, abs_start+400)
    if brace < 0:
        return src
    # already guarded?
    tail = src[brace:brace+220]
    if "__VSP_MINI_V7_ONLY" in tail:
        return src
    ins = "\n  if (window.__VSP_MINI_V7_ONLY) { return; }\n"
    return src[:brace+1] + ins + src[brace+1:]

# find all markers "/* ===== VSP_P1_DASH_MINICHARTS_"
positions = [m.start() for m in re.finditer(r'/\*\s*=====\s*VSP_P1_DASH_MINICHARTS_', s)]
patched = 0
for pos in positions:
    before = s
    s = inject_guard_after_iife_body(s, pos)
    if s != before:
        patched += 1

print("[OK] legacy minicharts guarded blocks:", patched, "markers_found:", len(positions))

# 2) Append V7 safe minicharts (API-based, tiny, bounded, no DOM-scan loops)
v7 = r"""
/* ===== VSP_P1_DASH_MINICHARTS_V7_ONLY_SAFE_V1 =====
   - Disable legacy minicharts (V1..V6) via window.__VSP_MINI_V7_ONLY
   - Render mini charts using /api/vsp/top_findings_v1 (no run_file_allow, no huge DOM scans)
   - Bounded work: limit items, 1 fetch, 1 render, no intervals
*/
(function(){
  try{
    if (window.__VSP_MINI_V7_INIT) return;
    window.__VSP_MINI_V7_INIT = true;

    function qs(sel, root){ try{return (root||document).querySelector(sel);}catch(e){return null;} }
    function qsa(sel, root){ try{return Array.from((root||document).querySelectorAll(sel));}catch(e){return [];} }
    function el(tag, attrs, text){
      var n=document.createElement(tag);
      if(attrs){ for(var k in attrs){ try{ n.setAttribute(k, String(attrs[k])); }catch(e){} } }
      if(text!=null) n.textContent = String(text);
      return n;
    }

    function getRID(){
      try{
        var u = new URL(location.href);
        var rid = u.searchParams.get("rid") || u.searchParams.get("RID");
        if(rid) return rid;
      }catch(e){}
      // try find in page text (cheap): a small number of candidates only
      var chips = qsa("a,button,span,div").slice(0,120);
      for(var i=0;i<chips.length;i++){
        var t=(chips[i].textContent||"").trim();
        if(t.startsWith("VSP_") && t.length<80) return t;
        if(t.includes("RID:")){
          var m=t.match(/RID:\s*([A-Za-z0-9_:-]{6,80})/);
          if(m) return m[1];
        }
      }
      return "";
    }

    function ensurePanel(){
      // Prefer to attach near bottom of Dashboard; fall back to body
      var host = qs("#vsp-dashboard-main") || qs("[data-tab='dashboard']") || qs("main") || qs("body");
      var id="vsp-mini-v7-panel";
      var old = qs("#"+id);
      if(old) return old;

      var wrap = el("div", {id:id});
      wrap.style.cssText = [
        "margin:14px 0 24px 0",
        "padding:14px 14px",
        "border:1px solid rgba(255,255,255,.08)",
        "border-radius:14px",
        "background:rgba(255,255,255,.03)",
        "backdrop-filter: blur(6px)"
      ].join(";");

      var h = el("div", null, "Mini Charts (safe)");
      h.style.cssText="font-weight:700;letter-spacing:.2px;font-size:13px;opacity:.92;margin:0 0 10px 0";
      wrap.appendChild(h);

      var sub = el("div", null, "Source: /api/vsp/top_findings_v1 (no allowlist file fetch).");
      sub.style.cssText="font-size:12px;opacity:.65;margin:0 0 10px 0";
      wrap.appendChild(sub);

      var body = el("div");
      body.id = "vsp-mini-v7-body";
      wrap.appendChild(body);

      try{ host.appendChild(wrap); }catch(e){ document.body.appendChild(wrap); }
      return wrap;
    }

    function barRow(label, val, total){
      var row = el("div");
      row.style.cssText="display:flex;align-items:center;gap:10px;margin:6px 0";

      var left = el("div", null, label);
      left.style.cssText="width:130px;font-size:12px;opacity:.85;white-space:nowrap;overflow:hidden;text-overflow:ellipsis";
      row.appendChild(left);

      var track = el("div");
      track.style.cssText="flex:1;height:10px;border-radius:999px;background:rgba(255,255,255,.06);overflow:hidden";
      var fill = el("div");
      var pct = total>0 ? Math.max(0, Math.min(100, (val*100/total))) : 0;
      fill.style.cssText="height:100%;width:"+pct.toFixed(1)+"%;border-radius:999px;background:rgba(120,170,255,.55)";
      track.appendChild(fill);
      row.appendChild(track);

      var right = el("div", null, String(val));
      right.style.cssText="width:52px;text-align:right;font-size:12px;opacity:.85";
      row.appendChild(right);

      return row;
    }

    function listBlock(title, arr){
      var box = el("div");
      box.style.cssText="margin-top:12px;padding-top:10px;border-top:1px dashed rgba(255,255,255,.10)";
      var h = el("div", null, title);
      h.style.cssText="font-weight:700;font-size:12px;opacity:.9;margin-bottom:8px";
      box.appendChild(h);

      var pre = el("pre");
      pre.style.cssText="margin:0;white-space:pre-wrap;word-break:break-word;font-size:12px;opacity:.85;line-height:1.35";
      pre.textContent = arr.length ? arr.join("\n") : "(no data)";
      box.appendChild(pre);
      return box;
    }

    function compute(items){
      var sev = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      var tool = {};
      var cwe = {};
      var risk = [];

      for(var i=0;i<items.length;i++){
        var it = items[i] || {};
        var s = String(it.severity||"").toUpperCase();
        if(sev[s] == null) sev[s]=0;
        sev[s]++;

        var tl = String(it.tool||"").toLowerCase() || "unknown";
        tool[tl] = (tool[tl]||0) + 1;

        var cw = it.cwe;
        if(cw!=null && cw!=="" && cw!=="None"){
          var k = String(cw);
          cwe[k] = (cwe[k]||0)+1;
        }

        if(risk.length < 10){
          var title = (it.title||it.rule||it.id||"").toString().slice(0,140);
          var file = (it.file||it.path||it.location||"").toString().slice(0,120);
          risk.push((s||"UNK") + "  " + (it.tool||"") + "  " + title + (file?("  ::  "+file):""));
        }
      }

      var toolTop = Object.entries(tool).sort(function(a,b){return b[1]-a[1]}).slice(0,8)
        .map(function(x){ return x[0] + "  " + x[1]; });

      var cweTop = Object.entries(cwe).sort(function(a,b){return b[1]-a[1]}).slice(0,8)
        .map(function(x){ return x[0] + "  " + x[1]; });

      return {sev:sev, toolTop:toolTop, cweTop:cweTop, risk:risk, total:items.length};
    }

    async function fetchTop(rid){
      var u = "/api/vsp/top_findings_v1?limit=400";
      if(rid) u += "&rid=" + encodeURIComponent(rid);

      var ctrl = new AbortController();
      var to = setTimeout(function(){ try{ctrl.abort();}catch(e){} }, 2500);

      try{
        var r = await fetch(u, {credentials:"same-origin", signal: ctrl.signal});
        var j = await r.json().catch(function(){ return null; });
        return j;
      } finally {
        clearTimeout(to);
      }
    }

    async function main(){
      var panel = ensurePanel();
      var body = qs("#vsp-mini-v7-body") || panel;
      body.textContent = "Loading /api/vsp/top_findings_v1 ...";

      var rid = getRID();
      var j = null;
      try{ j = await fetchTop(rid); }catch(e){ j = null; }

      if(!j || j.ok !== true){
        body.textContent = "No data (API unavailable): /api/vsp/top_findings_v1";
        return;
      }
      var items = j.items || j.findings || [];
      if(!Array.isArray(items) || !items.length){
        body.textContent = "No findings (items empty).";
        return;
      }

      // render
      body.textContent = "";
      var info = el("div", null, "RID=" + (j.run_id || rid || "(none)") + "  •  items(sample)=" + items.length);
      info.style.cssText="font-size:12px;opacity:.75;margin-bottom:10px";
      body.appendChild(info);

      var data = compute(items);
      var total = data.total || 0;

      body.appendChild(barRow("CRITICAL", data.sev.CRITICAL||0, total));
      body.appendChild(barRow("HIGH", data.sev.HIGH||0, total));
      body.appendChild(barRow("MEDIUM", data.sev.MEDIUM||0, total));
      body.appendChild(barRow("LOW", data.sev.LOW||0, total));
      body.appendChild(barRow("INFO", data.sev.INFO||0, total));
      body.appendChild(barRow("TRACE", data.sev.TRACE||0, total));

      body.appendChild(listBlock("By Tool (top 8)", data.toolTop));
      body.appendChild(listBlock("Top CWE (top 8)", data.cweTop));
      body.appendChild(listBlock("Top Risk (sample 10)", data.risk));
    }

    // run once, soon, no intervals
    setTimeout(function(){ main(); }, 80);
  }catch(e){}
})();
"""
s = s + "\n" + v7 + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check PASS: $JS" || { echo "[ERR] node --check FAIL: $JS"; node --check "$JS"; exit 2; }

echo "[DONE] Ctrl+Shift+R: http://127.0.0.1:8910/vsp5?rid=YOUR_RID"
echo "[HINT] open Console: should be no long-running loops anymore."
