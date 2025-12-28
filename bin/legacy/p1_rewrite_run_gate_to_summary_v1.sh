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
cp -f "$JS" "${JS}.bak_gate_rewrite_${TS}"
echo "[BACKUP] ${JS}.bak_gate_rewrite_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_REWRITE_RUN_GATE_TO_SUMMARY_V1"
if MARK in s:
    print("[SKIP] marker already present:", MARK)
    raise SystemExit(0)

patch = r"""
/* ===================== VSP_P1_REWRITE_RUN_GATE_TO_SUMMARY_V1 =====================
   Force commercial behavior:
   - Any auto-load of run_gate.json is rewritten to run_gate_summary.json (smaller, KPI-ready)
   - Works for BOTH fetch and XMLHttpRequest (axios)
================================================================================== */
(()=> {
  try {
    if (window.__vsp_p1_gate_rewrite_v1) return;
    window.__vsp_p1_gate_rewrite_v1 = true;

    const rewrite = (u) => {
      if (!u) return u;
      const s = String(u);
      if (s.includes("/api/vsp/run_file_allow") && s.includes("path=run_gate.json")) {
        return s.replace("path=run_gate.json", "path=run_gate_summary.json");
      }
      return u;
    };

    // --- fetch
    if (window.fetch && !window.__vsp_p1_gate_rewrite_fetch_v1) {
      window.__vsp_p1_gate_rewrite_fetch_v1 = true;
      const prevFetch = window.fetch.bind(window);
      window.fetch = (input, init) => {
        try {
          if (typeof input === "string") {
            const u2 = rewrite(input);
            if (u2 !== input) {
              console.warn("[VSP][rewrite] fetch:", input, "=>", u2);
              input = u2;
            }
          } else if (input && input.url) {
            const u2 = rewrite(input.url);
            if (u2 !== input.url) {
              console.warn("[VSP][rewrite] fetch req:", input.url, "=>", u2);
              // best-effort: create new Request preserving init
              input = new Request(u2, input);
            }
          }
        } catch(_) {}
        return prevFetch(input, init);
      };
    }

    // --- XHR (axios)
    if (window.XMLHttpRequest && !window.__vsp_p1_gate_rewrite_xhr_v1) {
      window.__vsp_p1_gate_rewrite_xhr_v1 = true;
      const XHR = window.XMLHttpRequest;
      const _open = XHR.prototype.open;

      XHR.prototype.open = function(method, url) {
        try {
          const u2 = rewrite(url);
          if (u2 !== url) {
            console.warn("[VSP][rewrite] XHR:", url, "=>", u2);
            url = u2;
          }
        } catch(_) {}
        return _open.apply(this, [method, url, ...Array.prototype.slice.call(arguments, 2)]);
      };
    }

    console.log("[VSP] gate rewrite to summary enabled");
  } catch(e) {
    try { console.warn("[VSP] gate rewrite init error:", e); } catch(_){}
  }
})();
/* ===================== /VSP_P1_REWRITE_RUN_GATE_TO_SUMMARY_V1 ===================== */
"""

p.write_text(patch + "\n" + s, encoding="utf-8")
print("[OK] patched:", p)
PY

command -v node >/dev/null 2>&1 && node --check "$JS" && echo "[OK] node --check passed" || true
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] gate rewrite patch applied."
