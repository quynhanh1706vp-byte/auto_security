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
cp -f "$JS" "${JS}.bak_rungateok_${TS}"
echo "[BACKUP] ${JS}.bak_rungateok_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

js_path = Path("static/js/vsp_bundle_commercial_v2.js")
s = js_path.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RUN_GATE_SUMMARY_OK_NORMALIZE_V1"
if MARK in s:
    print("[SKIP] marker already present:", MARK)
    raise SystemExit(0)

patch = r"""
/* ===================== VSP_P1_RUN_GATE_SUMMARY_OK_NORMALIZE_V1 =====================
   Normalize /api/vsp/run_file_allow?path=run_gate_summary.json (and run_gate.json):
   - If JSON lacks 'ok', inject ok:true
   - Also inject rid/run_id from query if missing
===================================================================================== */
(()=> {
  try {
    if (window.__vsp_p1_rungate_ok_norm_v1) return;
    window.__vsp_p1_rungate_ok_norm_v1 = true;

    const prevFetch = window.fetch ? window.fetch.bind(window) : null;
    if (!prevFetch) return;

    const isGateSummaryUrl = (u) => {
      if (!u) return false;
      const s = String(u);
      if (!s.includes("/api/vsp/run_file_allow")) return false;
      if (s.includes("path=run_gate_summary.json")) return true;
      if (s.includes("path=run_gate.json")) return true;
      return false;
    };

    const getRidFromUrl = (u) => {
      try {
        const url = new URL(u, window.location.origin);
        return url.searchParams.get("rid") || "";
      } catch(_) { return ""; }
    };

    window.fetch = async (input, init) => {
      const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
      const resp = await prevFetch(input, init);

      if (!isGateSummaryUrl(url)) return resp;

      try {
        const ct = (resp.headers && resp.headers.get) ? (resp.headers.get("content-type") || "") : "";
        if (!ct.includes("application/json")) return resp;

        const txt = await resp.clone().text();
        let j = null;
        try { j = JSON.parse(txt); } catch(_e) { return resp; }
        if (!j || typeof j !== "object") return resp;

        // inject ok if missing (this is the critical fix)
        if (!("ok" in j)) j.ok = true;

        // inject rid/run_id if missing
        const rid = getRidFromUrl(url);
        if (rid) {
          if (!("rid" in j)) j.rid = rid;
          if (!("run_id" in j)) j.run_id = rid;
        }

        const h = new Headers(resp.headers || {});
        h.set("content-type", "application/json");

        const body = JSON.stringify(j);
        return new Response(body, { status: resp.status, headers: h });
      } catch (e) {
        try { console.warn("[VSP][rungate_ok_norm] error:", e); } catch(_){}
        return resp;
      }
    };

    try { console.log("[VSP] run_gate_summary ok-normalize enabled"); } catch(_){}
  } catch(_e) {}
})();
/* ===================== /VSP_P1_RUN_GATE_SUMMARY_OK_NORMALIZE_V1 ===================== */
"""

js_path.write_text(patch + "\n" + s, encoding="utf-8")
print("[OK] patched:", js_path)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check passed"
else
  echo "[WARN] node not found; skip node --check"
fi

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] run_gate_summary ok-normalize patch applied."
