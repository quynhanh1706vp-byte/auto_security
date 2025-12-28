#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need grep; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_runsqueue_${TS}"
echo "[BACKUP] ${JS}.bak_runsqueue_${TS}"

export TS
python3 - <<'PY'
from pathlib import Path
import os, re

ts = os.environ.get("TS","")
p = Path("static/js/vsp_p1_page_boot_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RUNS_THROTTLE_QUEUE_V1"
if MARK in s:
    print("[OK] marker already present:", MARK)
    raise SystemExit(0)

header = "\n/* " + MARK + " " + ts + " */\n"

code = r"""
(function(){
  try{
    if (window.__VSP_P1_RUNS_THROTTLE_QUEUE_V1__) return;
    window.__VSP_P1_RUNS_THROTTLE_QUEUE_V1__ = true;

    var realFetch = window.fetch ? window.fetch.bind(window) : null;
    if (!realFetch) return;

    var lastRunsAt = 0;
    var lastDashAt = 0;
    var q = Promise.resolve();

    function sleep(ms){ return new Promise(function(r){ setTimeout(r, ms); }); }

    function isRuns(u){ return (typeof u === "string") && u.indexOf("/api/vsp/runs") !== -1; }
    function isDash(u){ return (typeof u === "string") && u.indexOf("/api/vsp/dashboard") !== -1; }

    function clearFailedBox(){
      try{
        // clear common “Failed to load … HTTP …” area
        var nodes = document.querySelectorAll("body *");
        for (var i=0;i<nodes.length;i++){
          var t = (nodes[i].textContent || "").trim();
          if (t.startsWith("Failed to load dashboard data") || t.indexOf("HTTP 503 /api/vsp/runs") !== -1){
            nodes[i].textContent = "";
          }
        }
      }catch(_){}
    }

    window.fetch = function(input, init){
      var url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
      if (isRuns(url) || isDash(url)){
        q = q.then(async function(){
          var now = Date.now();
          var minMs = isRuns(url) ? 1200 : 800; // thương mại: throttle nhưng KHÔNG fail
          var last = isRuns(url) ? lastRunsAt : lastDashAt;
          var wait = (last + minMs) - now;
          if (wait > 0) await sleep(wait);
          if (isRuns(url)) lastRunsAt = Date.now(); else lastDashAt = Date.now();
          var r = await realFetch(input, init);
          try{
            if (isRuns(url) && r && r.status === 200) clearFailedBox();
          }catch(_){}
          return r;
        });
        return q;
      }
      return realFetch(input, init);
    };

  }catch(_){}
})();
"""

p.write_text(s + "\n" + header + code + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

# bump cache-bust v=TS for bootjs in 4 templates
python3 - <<'PY'
from pathlib import Path
import os, re
ts=os.environ.get("TS","")
tpls=[
  "templates/vsp_5tabs_enterprise_v2.html",
  "templates/vsp_dashboard_2025.html",
  "templates/vsp_data_source_v1.html",
  "templates/vsp_rule_overrides_v1.html",
]
for t in tpls:
  p=Path(t)
  if not p.exists(): 
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  s2=re.sub(r'(/static/js/vsp_p1_page_boot_v1\.js)\?v=[0-9_]+', r'\1?v='+ts, s)
  p.write_text(s2, encoding="utf-8")
print("[OK] templates bootjs cache-bust =>", ts)
PY

echo "[OK] restart UI"
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  rm -f /tmp/vsp_ui_8910.lock || true
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || true
fi

echo "== verify marker =="
grep -n "VSP_P1_RUNS_THROTTLE_QUEUE_V1" static/js/vsp_p1_page_boot_v1.js | head -n 2 || true
echo "== verify vsp5 bootjs url =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_p1_page_boot_v1.js" | head -n 2 || true
echo "[NEXT] Mở Incognito /vsp5 (khuyến nghị) hoặc Ctrl+F5."
