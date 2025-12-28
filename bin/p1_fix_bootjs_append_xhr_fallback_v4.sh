#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need curl; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_xhr_v4_${TS}"
echo "[BACKUP] ${JS}.bak_xhr_v4_${TS}"

export TS
python3 - <<'PY'
from pathlib import Path
import os

p = Path("static/js/vsp_p1_page_boot_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_XHR_RUNS_FALLBACK_V4"
if MARK in s:
    print("[OK] marker already present:", MARK)
    raise SystemExit(0)

ts = os.environ.get("TS","")

header = "\n/* " + MARK + " " + ts + " */\n"

# NOTE: raw JS string, NO f-string, NO .format(), to avoid brace parsing issues.
code = r"""
(function(){
  try{
    if (window.__VSP_P1_XHR_RUNS_FALLBACK_V4__) return;
    window.__VSP_P1_XHR_RUNS_FALLBACK_V4__ = true;

    function xhrJson(url, timeoutMs){
      return new Promise(function(resolve, reject){
        try{
          var x = new XMLHttpRequest();
          x.open("GET", url, true);
          x.timeout = timeoutMs || 8000;
          x.setRequestHeader("Cache-Control", "no-store");
          x.setRequestHeader("Pragma", "no-cache");
          x.onreadystatechange = function(){
            if (x.readyState !== 4) return;
            var st = x.status || 0;
            if (st !== 200) return reject({status: st});
            try{
              resolve(JSON.parse(x.responseText || "{}"));
            }catch(e){
              reject({status: 598});
            }
          };
          x.ontimeout = function(){ reject({status: 599}); };
          x.onerror = function(){ reject({status: 597}); };
          x.send();
        }catch(e){
          reject({status: 596});
        }
      });
    }

    function ensureBanner(msg){
      try{
        var id = "vsp_degraded_banner_v4";
        var el = document.getElementById(id);
        if (!el){
          el = document.createElement("div");
          el.id = id;
          el.className = "vsp-degraded-banner";
          (document.querySelector(".vsp-card,.card,.panel,.box") || document.body).prepend(el);
        }
        el.textContent = msg;
      }catch(_){}
    }

    async function run(){
      var path = (location.pathname || "");
      if (!path.includes("vsp5")) return;

      try{
        var runs = await xhrJson("/api/vsp/runs?limit=1&_ts=" + Date.now(), 8000);
        if (runs && runs.ok && runs.rid_latest){
          window.__VSP_RID_LATEST__ = runs.rid_latest;
          return;
        }
        ensureBanner("DEGRADED: runs api non-ok (UI continues)");
      }catch(e){
        ensureBanner("DEGRADED: cannot load runs via XHR (status=" + (e && e.status) + ") (UI continues)");
      }
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run);
    else run();
  }catch(_){}
})();
"""

p.write_text(s + "\n" + header + code + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "[OK] restart UI"
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  rm -f /tmp/vsp_ui_8910.lock || true
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || true
fi

echo "== verify marker in bootjs =="
grep -n "VSP_P1_XHR_RUNS_FALLBACK_V4" static/js/vsp_p1_page_boot_v1.js | head -n 2 || true
echo "== verify vsp5 includes bootjs =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_p1_page_boot_v1.js" | head -n 2 || true
echo "[NEXT] Mở Incognito /vsp5 hoặc Ctrl+F5."
