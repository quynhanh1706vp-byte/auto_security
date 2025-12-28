#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_badges_${TS}"
echo "[BACKUP] ${JS}.bak_badges_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_BADGES_RID_OVERALL_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Insert before the LAST occurrence of "})();" (end of IIFE)
idx = s.rfind("})();")
if idx < 0:
    raise SystemExit("[ERR] cannot find IIFE ending '})();' in bundle file")

snippet = r"""
  // ===================== VSP_P2_BADGES_RID_OVERALL_V1 =====================
  (function(){
    function safeLog(){ try{ console.log.apply(console, arguments); }catch(e){} }
    function safeWarn(){ try{ console.warn.apply(console, arguments); }catch(e){} }

    function ensureStyle(){
      if (document.getElementById("vsp_p2_badges_style")) return;
      var st = document.createElement("style");
      st.id = "vsp_p2_badges_style";
      st.textContent = `
        .vsp-p2-badges{display:flex;gap:8px;align-items:center;margin-left:auto}
        .vsp-badge{font:12px/1.2 ui-sans-serif,system-ui; padding:4px 8px; border-radius:999px;
          border:1px solid rgba(255,255,255,.18); background:rgba(255,255,255,.06); color:#e8eefc;
          letter-spacing:.2px; white-space:nowrap}
        .vsp-badge b{font-weight:700}
        .vsp-badge.green{border-color:rgba(46,204,113,.45); background:rgba(46,204,113,.12)}
        .vsp-badge.amber{border-color:rgba(241,196,15,.45); background:rgba(241,196,15,.12)}
        .vsp-badge.red{border-color:rgba(231,76,60,.45); background:rgba(231,76,60,.12)}
        .vsp-badge.gray{opacity:.85}
      `;
      document.head.appendChild(st);
    }

    function findTopbar(){
      // Your pages use .topnav in /vsp5; other tabs may also have it.
      return document.querySelector(".topnav") || document.querySelector("#topbar") || null;
    }

    function ensureContainer(topbar){
      var id = "vsp_p2_badges";
      var c = document.getElementById(id);
      if (c) return c;
      c = document.createElement("div");
      c.id = id;
      c.className = "vsp-p2-badges";
      if (topbar){
        topbar.appendChild(c);
      } else {
        // fallback: put at top of body (should rarely happen)
        c.style.position = "fixed";
        c.style.top = "10px";
        c.style.right = "10px";
        c.style.zIndex = "9999";
        document.body.appendChild(c);
      }
      return c;
    }

    function mkBadge(cls, text){
      var el = document.createElement("span");
      el.className = "vsp-badge " + cls;
      el.textContent = text;
      return el;
    }

    function timeoutFetch(url, ms){
      var ctrl = new AbortController();
      var t = setTimeout(function(){ try{ ctrl.abort(); }catch(e){} }, ms);
      return fetch(url, {cache:"no-store", credentials:"same-origin", signal: ctrl.signal})
        .finally(function(){ clearTimeout(t); });
    }

    function pickOverallClass(v){
      v = (v || "").toString().toUpperCase();
      if (v === "GREEN" || v === "PASS" || v === "OK") return "green";
      if (v === "AMBER" || v === "WARN" || v === "WARNING" || v === "DEGRADED") return "amber";
      if (v === "RED" || v === "FAIL" || v === "BLOCK") return "red";
      return "gray";
    }

    function shortRid(rid){
      rid = (rid || "").toString();
      if (rid.length <= 18) return rid;
      return rid.slice(0, 10) + "…" + rid.slice(-6);
    }

    async function run(){
      try{
        ensureStyle();
        var topbar = findTopbar();
        var c = ensureContainer(topbar);

        // clear old
        c.innerHTML = "";
        c.appendChild(mkBadge("gray", "RID: …"));
        c.appendChild(mkBadge("gray", "Overall: …"));

        // 1) rid_latest
        var rid = "";
        try{
          var r1 = await timeoutFetch("/api/vsp/rid_latest?ts=" + Date.now(), 3500);
          var j1 = await r1.json();
          rid = (j1 && j1.rid) ? j1.rid : "";
        }catch(e){
          safeWarn("[P2Badges] rid_latest fetch fail", e);
        }

        // 2) run_gate_summary
        var overall = "";
        var degraded = false;
        try{
          if (rid){
            var url = "/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json&ts=" + Date.now();
            var r2 = await timeoutFetch(url, 4000);
            var j2 = await r2.json();

            overall = (j2 && j2.overall) ? j2.overall : "";
            // Best-effort degraded detection (flexible)
            degraded = !!(
              (j2 && j2.degraded) ||
              (j2 && j2.status && (""+j2.status).toUpperCase().includes("DEGRADED")) ||
              (j2 && j2.degraded_tools && Array.isArray(j2.degraded_tools) && j2.degraded_tools.length) ||
              (j2 && j2.missing_tools && Array.isArray(j2.missing_tools) && j2.missing_tools.length)
            );
          }
        }catch(e){
          safeWarn("[P2Badges] run_gate_summary fetch fail", e);
        }

        // render
        c.innerHTML = "";
        c.appendChild(mkBadge("gray", "RID: " + (rid ? shortRid(rid) : "n/a")));
        var oc = pickOverallClass(overall);
        c.appendChild(mkBadge(oc, "Overall: " + (overall ? overall.toString().toUpperCase() : "n/a")));
        if (degraded){
          c.appendChild(mkBadge("amber", "DEGRADED"));
        }

        safeLog("[P2Badges] ok rid=", rid, "overall=", overall, "degraded=", degraded);
      }catch(e){
        // no throw to avoid breaking UI
      }
    }

    // Run after DOM is ready enough
    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", run);
    } else {
      run();
    }
  })();
  // ===================== /VSP_P2_BADGES_RID_OVERALL_V1 =====================
"""

s2 = s[:idx] + snippet + "\n" + s[idx:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted badges snippet")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check $JS"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] P2 badges applied. Reload browser pages to see RID/Overall/DEGRADED badges."
