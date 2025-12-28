#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need systemctl

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_hooks_${TS}"
echo "[BACKUP] ${JS}.bak_hooks_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_CLIENT_REFRESH_HOOKS_V1_SAFEAPPEND"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

code = textwrap.dedent(r"""
;(()=> {
  try{
    // ===================== VSP_P2_CLIENT_REFRESH_HOOKS_V1_SAFEAPPEND =====================
    // Goal: refresh dashboard/runs without full page reload (enterprise feel).

    const sleep = (ms)=> new Promise(r=> setTimeout(r, ms));

    function isVisible(el){
      try{
        if (!el) return false;
        const r = el.getBoundingClientRect();
        return !!(r.width && r.height) && getComputedStyle(el).visibility !== "hidden";
      }catch(e){ return false; }
    }

    function clickTabSoft(tabName){
      try{
        const t = (tabName||"").trim();
        if (!t) return false;

        const cand = [
          `button[data-vsp-tab="${t}"]`,
          `a[data-vsp-tab="${t}"]`,
          `#tab_${t}`, `#vsp_tab_${t}`,
          `button[data-tab="${t}"]`,
          `a[href*="${t}"]`,
          `button[id*="${t}"]`,
        ];

        for (const sel of cand){
          const el = document.querySelector(sel);
          if (el && isVisible(el)){
            el.click();
            return true;
          }
        }
      }catch(e){}
      return false;
    }

    async function refreshGateIntoCards(rid){
      try{
        if (!rid) return false;

        // Prefer reports/ then fallback root (your P1 helper already does this safely)
        let gate = null;

        if (window.__vsp_runfileallow_fetch_v1){
          const g = await window.__vsp_runfileallow_fetch_v1({ base:"", rid, path:"reports/run_gate_summary.json", acceptJson:true });
          if (g && g.ok) gate = g.data;
        } else {
          // fallback: direct fetch (still ok because backend now aliases)
          const r = await fetch(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent("reports/run_gate_summary.json")}`, { credentials:"same-origin" });
          if (r.ok) gate = await r.json();
        }

        if (gate && typeof window.__vsp_dash_bind_native_cards_v7_apply === "function"){
          try{ window.__vsp_dash_bind_native_cards_v7_apply(gate); }catch(e){}
          return true;
        }
      }catch(e){}
      return false;
    }

    // ---- Public hooks used by autorefresh poller ----
    window.__vsp_refresh_dashboard = async function(rid){
      try{
        window.__vsp_latest_rid = rid || window.__vsp_latest_rid;

        // Try apply gate into native cards (fast, no flicker)
        const ok = await refreshGateIntoCards(window.__vsp_latest_rid);

        // Optional tiny badge (non-spam)
        try{
          if (ok && window.__vsp_badge_degraded_v1){
            // re-use badge style but different message; auto-disappears
            window.__vsp_badge_degraded_v1(`UPDATED: ${window.__vsp_latest_rid}`);
          }
        }catch(e){}

        return ok;
      }catch(e){ return false; }
    };

    window.__vsp_refresh_runs = async function(rid){
      try{
        window.__vsp_latest_rid = rid || window.__vsp_latest_rid;

        // Soft refresh: re-click current tab so existing renderOnce() runs again
        let cur = "";
        try{ cur = (typeof window.__vsp_tab === "function" ? window.__vsp_tab() : "") || ""; }catch(e){}
        if (cur) {
          if (clickTabSoft(cur)) return true;
        }

        // fallback: try common tab names
        if (clickTabSoft("runs")) return true;
        if (clickTabSoft("runs_reports")) return true;

        // last resort: do nothing (autorefresh poller will reload only if it can't call hooks)
        await sleep(0);
        return false;
      }catch(e){ return false; }
    };

  }catch(e){}
})();
""").strip("\n") + "\n"

p.write_text(s + ("\n" if not s.endswith("\n") else "") + code, encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check "$JS"
echo "[OK] node --check"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[OK] restarted"
