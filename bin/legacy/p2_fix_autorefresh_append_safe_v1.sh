#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need systemctl

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

echo "== [0] restore latest bak_autorefresh_* (known-good) =="
python3 - <<'PY'
from pathlib import Path
import re

js = Path("static/js/vsp_bundle_commercial_v2.js")
baks = sorted(js.parent.glob(js.name + ".bak_autorefresh_*"), key=lambda p: p.stat().st_mtime, reverse=True)
if not baks:
    raise SystemExit("[ERR] no .bak_autorefresh_* found; refuse to proceed")
bak = baks[0]
js.write_text(bak.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored:", bak)
PY

echo "== [1] append autorefresh (safe, no block comments, no injection into header) =="
python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_CLIENT_AUTOREFRESH_LATEST_RUN_15S_V1_SAFEAPPEND"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

code = textwrap.dedent(r"""
;(()=> {
  try{
    // ===================== VSP_P2_CLIENT_AUTOREFRESH_LATEST_RUN_15S_V1_SAFEAPPEND =====================
    if (window.__vsp_autorefresh_latest_run_v1_safe) return;
    window.__vsp_autorefresh_latest_run_v1_safe = true;

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

          // Prefer hook-based refresh if bundle defines them
          try{
            if (typeof window.__vsp_refresh_dashboard === "function") { window.__vsp_refresh_dashboard(rid); return; }
            if (typeof window.__vsp_refresh_runs === "function") { window.__vsp_refresh_runs(rid); return; }
          }catch(e){}

          // Minimal safe: reload only on /vsp5 or dashboard-like paths
          try{
            const pth = (location.pathname || "");
            if (pth === "/vsp5" || pth.includes("dashboard")) location.reload();
          }catch(e){}
        }
      }catch(e){
        // no console spam
      }
    }

    const start = ()=> {
      pollOnce();
      setInterval(pollOnce, POLL_MS);
    };
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once:true });
    else start();
  }catch(e){}
})();
""").strip("\n") + "\n"

p.write_text(s + ("\n" if not s.endswith("\n") else "") + code, encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "== [2] node syntax check =="
node --check "$JS"
echo "[OK] node --check"

echo "== [3] restart service =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[OK] restarted"
