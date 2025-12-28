#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_lazyfind_${TS}"
echo "[BACKUP] ${JS}.bak_lazyfind_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

js_path = Path("static/js/vsp_bundle_commercial_v2.js")
s = js_path.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_LAZY_BIG_FINDINGS_FETCH_V1"
if MARK in s:
    print("[SKIP] marker already present:", MARK)
    raise SystemExit(0)

patch = r"""
/* ===================== VSP_P1_LAZY_BIG_FINDINGS_FETCH_V1 =====================
   Goal: prevent auto-load of big findings_unified.json on dashboard load/polling.
   Allow big fetch only after user gesture (click/keydown/pointer) within a short window,
   or when explicitly enabled via window.__vsp_enable_big_findings_once().
========================================================================== */
(()=> {
  try {
    if (window.__vsp_p1_lazy_big_findings_fetch_v1) return;
    window.__vsp_p1_lazy_big_findings_fetch_v1 = true;

    let __lastGesture = 0;
    const mark = () => { __lastGesture = Date.now(); };
    ["click","keydown","pointerdown","touchstart","mousedown"].forEach(ev=>{
      window.addEventListener(ev, mark, true);
    });

    const ZERO_COUNTS = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
    const shouldGate = (url) => {
      if (!url) return false;
      const u = String(url);
      // gate the big one(s)
      if (u.includes("/api/vsp/run_file_allow") && u.includes("path=findings_unified.json")) return true;
      // optional: also gate other large exports if they ever get auto-loaded
      if (u.includes("/api/vsp/run_file_allow") && u.includes("path=findings_unified.") && !u.includes("run_gate")) return true;
      return false;
    };

    window.__vsp_enable_big_findings_once = () => {
      window.__vsp_allow_big_findings = true;
      setTimeout(()=>{ try{ window.__vsp_allow_big_findings = false; }catch(_){ } }, 8000);
      return true;
    };

    const realFetch = window.fetch ? window.fetch.bind(window) : null;
    if (!realFetch) return;

    window.fetch = async (input, init) => {
      const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
      if (shouldGate(url)) {
        const now = Date.now();
        const allow =
          (window.__vsp_allow_big_findings === true) ||
          ((now - __lastGesture) >= 0 && (now - __lastGesture) < 2000);

        if (!allow) {
          // Return a safe empty payload (ok:true) so UI won't hang on skeleton.
          const body = JSON.stringify({
            ok: true,
            meta: { counts_by_severity: ZERO_COUNTS, note: "lazy_skip_big_findings" },
            findings: []
          });
          try { console.warn("[VSP][lazy] skip big auto-fetch:", url); } catch(_){}
          return new Response(body, { status: 200, headers: {"Content-Type":"application/json"} });
        }
      }
      return realFetch(input, init);
    };
  } catch (e) {
    try { console.warn("[VSP][lazy] init error:", e); } catch(_){}
  }
})();
/* ===================== /VSP_P1_LAZY_BIG_FINDINGS_FETCH_V1 ===================== */
"""

# Prepend patch (safe for both minified/unminified bundles)
js_path.write_text(patch + "\n" + s, encoding="utf-8")
print("[OK] patched:", js_path)
PY

# sanity check
if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check passed"
else
  echo "[WARN] node not found; skip node --check"
fi

# restart service if exists (ignore errors)
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] lazy-load big findings patch applied."
