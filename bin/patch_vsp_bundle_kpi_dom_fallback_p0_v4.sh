#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_bundle_commercial_v2.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_dom_${TS}"
echo "[BACKUP] $F.bak_kpi_dom_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_KPI_DOM_FALLBACK_P0_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
/* VSP_KPI_DOM_FALLBACK_P0_V4: force KPI numbers from dashboard gate counts (DOM-safe) */
(function(){
  try{
    if (window.__VSP_KPI_DOM_FALLBACK_P0_V4) return;
    window.__VSP_KPI_DOM_FALLBACK_P0_V4 = 1;

    function upper(x){ return String(x||"").trim().toUpperCase(); }
    function num(x){ x = (x===null||x===undefined) ? 0 : x; var n=+x; return isFinite(n)?n:0; }

    function extractCounts(d){
      try{
        var c = d && d.gate && (d.gate.counts_total || d.gate.counts) ? (d.gate.counts_total || d.gate.counts) : null;
        if (!c && d && d.by_severity) c = d.by_severity;
        if (!c && d && d.kpi) c = {CRITICAL:d.kpi.critical,HIGH:d.kpi.high,MEDIUM:d.kpi.medium,LOW:d.kpi.low,INFO:d.kpi.info,TRACE:d.kpi.trace};
        if (!c) c = {};
        var CR=num(c.CRITICAL), HI=num(c.HIGH), ME=num(c.MEDIUM), LO=num(c.LOW), IN=num(c.INFO), TR=num(c.TRACE);
        return {CRITICAL:CR,HIGH:HI,MEDIUM:ME,LOW:LO,INFO:IN,TRACE:TR,TOTAL:(CR+HI+ME+LO+IN+TR)};
      }catch(_){ return {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0,TOTAL:0}; }
    }

    function findValueNodeNearLabel(label){
      try{
        var want = upper(label);
        var candidates = Array.from(document.querySelectorAll("span,div,button,strong,small,h1,h2,h3,h4,h5")).filter(function(el){
          if(!el) return false;
          var t = upper(el.textContent);
          return t===want;
        });
        for (var i=0;i<candidates.length;i++){
          var e = candidates[i];
          var card = (e.closest && (e.closest(".kpi, .kpi-card, .card, .tile, .panel") || e.closest("div"))) || e.parentElement;
          if(!card) continue;
          var v = card.querySelector(".kpi-value, .kpiValue, .value, .num, .count, .metric, .kpiNum");
          if (v) return v;
          // fallback: find first "number-like" node inside same card
          var nodes = Array.from(card.querySelectorAll("span,div,strong"));
          for (var j=0;j<nodes.length;j++){
            var t = (nodes[j].textContent||"").trim();
            if (/^\d+$/.test(t)) return nodes[j];
          }
        }
      }catch(_){}
      return null;
    }

    function setKpi(label, value){
      try{
        // prefer explicit ids if any
        var ids = [
          "kpi_"+label.toLowerCase(), "kpi-"+label.toLowerCase(),
          "kpi_"+label.toUpperCase(), "kpi-"+label.toUpperCase(),
          label.toLowerCase()+"_kpi", label.toUpperCase()+"_kpi"
        ];
        for (var i=0;i<ids.length;i++){
          var el = document.getElementById(ids[i]);
          if (el){ el.textContent = String(value); return true; }
        }
        var v = findValueNodeNearLabel(label);
        if (v){ v.textContent = String(value); return true; }
      }catch(_){}
      return false;
    }

    async function fetchDash(){
      try{
        var r = await fetch("/api/vsp/dashboard_commercial_v2");
        if (!r || !r.ok) return null;
        return await r.json().catch(function(){ return null; });
      }catch(_){ return null; }
    }

    async function tick(){
      try{
        if (location.hash && location.hash.toLowerCase().indexOf("dashboard")<0) return;
        var d = await fetchDash();
        if (!d) return;
        var c = extractCounts(d);
        setKpi("TOTAL", c.TOTAL);
        setKpi("CRITICAL", c.CRITICAL);
        setKpi("HIGH", c.HIGH);
        setKpi("MEDIUM", c.MEDIUM);
        setKpi("LOW", c.LOW);
      }catch(_){}
    }

    function schedule(){
      var tries = 0;
      (function loop(){
        tries++;
        tick();
        if (tries < 12) setTimeout(loop, tries < 5 ? 400 : 1200);
      })();
    }

    window.addEventListener("hashchange", schedule);
    window.addEventListener("load", schedule);
    if (document.readyState === "complete" || document.readyState === "interactive") schedule();
  }catch(_){}
})();
'''

# inject near 'use strict' if possible
idx = s.find("'use strict'")
if idx!=-1:
    s = s[:idx] + inject + s[idx:]
else:
    s = inject + "\n" + s

s += f"\n/* {MARK} */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check "$F"
echo "[OK] node --check OK"
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R http://127.0.0.1:8910/vsp4 (Dashboard KPI should match gate counts)"
