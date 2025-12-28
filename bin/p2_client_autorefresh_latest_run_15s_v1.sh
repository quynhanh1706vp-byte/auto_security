#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_autorefresh_${TS}"
echo "[BACKUP] ${JS}.bak_autorefresh_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_CLIENT_AUTOREFRESH_LATEST_RUN_15S_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

code = textwrap.dedent(r"""
/* ===================== VSP_P2_CLIENT_AUTOREFRESH_LATEST_RUN_15S_V1 =====================
   Commercial UX: auto-detect new latest run and refresh panels without console spam.
====================================================================================== */
(()=> {
  try{
    if (window.__vsp_autorefresh_latest_run_v1) return;
    window.__vsp_autorefresh_latest_run_v1 = true;

    const POLL_MS = 15000;

    async function pollOnce(){
      try{
        const r = await fetch("/api/vsp/runs?limit=1", { credentials:"same-origin" });
        if (!r.ok) return;
        const j = await r.json();
        const item = (j && j.items && j.items[0]) || null;
        const rid = (item && (item.run_id || item.rid)) || (j && j.latest_rid) || null;
        if (!rid) return;

        const prev = window.__vsp_latest_rid || null;
        window.__vsp_latest_rid = rid;

        if (prev && prev !== rid){
          try{
            window.dispatchEvent(new CustomEvent("vsp:latest_run_changed", { detail:{ prev, rid } }));
          }catch(e){}

          // If there are known refresh hooks, call them; else soft reload only on Dashboard view.
          try{
            if (typeof window.__vsp_refresh_dashboard === "function") { window.__vsp_refresh_dashboard(rid); return; }
            if (typeof window.__vsp_refresh_runs === "function") { window.__vsp_refresh_runs(rid); return; }
          }catch(e){}

          // Minimal safe behavior: reload only if on /vsp5 or dashboard-like pages.
          try{
            const p = (location.pathname || "");
            if (p === "/vsp5" || p.includes("dashboard")) location.reload();
          }catch(e){}
        }
      }catch(e){
        // no spam
      }
    }

    // prime quickly after DOM ready
    const start = ()=> {
      pollOnce();
      setInterval(pollOnce, POLL_MS);
    };
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once:true });
    else start();
  }catch(e){}
})();
""").strip("\n") + "\n"

# inject after the previous P1 marker block if present, else near top
pos = s.find("VSP_P1_CLIENT_RUNFILEALLOW_FALLBACK_V1")
if pos != -1:
    ins = s.find("\n", pos)
    if ins == -1: ins = 0
    s2 = s[:ins+1] + code + s[ins+1:]
else:
    # after first IIFE opening if possible
    ins_at = s.find("(()=>")
    if ins_at != -1:
        nl = s.find("\n", ins_at)
        if nl == -1: nl = 0
        s2 = s[:nl+1] + code + s[nl+1:]
    else:
        s2 = code + "\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

node --check "$JS"
echo "[OK] node --check"
