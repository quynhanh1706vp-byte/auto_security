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
cp -f "$JS" "${JS}.bak_rungateok_v2_${TS}"
echo "[BACKUP] ${JS}.bak_rungateok_v2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RUN_GATE_SUMMARY_OK_NORMALIZE_V2"
if MARK in s:
    print("[SKIP] marker already present:", MARK)
    raise SystemExit(0)

patch = r"""
/* ===================== VSP_P1_RUN_GATE_SUMMARY_OK_NORMALIZE_V2 =====================
   Strong normalize for run_gate_summary.json / run_gate.json:
   - Parse JSON regardless of content-type (some gateways send text/plain)
   - Inject ok:true, rid/run_id
   - Inject meta.counts_by_severity (for KPI) if missing by aggregating known shapes
===================================================================================== */
(()=> {
  try {
    if (window.__vsp_p1_rungate_ok_norm_v2) return;
    window.__vsp_p1_rungate_ok_norm_v2 = true;

    const SEV = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const ZERO = ()=>({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0});

    const addCounts = (dst, src) => {
      if (!src || typeof src !== "object") return dst;
      SEV.forEach(k => { const v = Number(src[k]||0); if (!Number.isNaN(v)) dst[k] += v; });
      return dst;
    };

    const tryExtractCounts = (j) => {
      // 1) counts_total already a dict by severity?
      if (j && typeof j.counts_total === "object") {
        const c = ZERO();
        addCounts(c, j.counts_total);
        const sum = SEV.reduce((a,k)=>a+c[k],0);
        if (sum > 0) return c;
      }
      // 2) top-level counts_by_severity?
      if (j && typeof j.counts_by_severity === "object") {
        const c = ZERO();
        addCounts(c, j.counts_by_severity);
        const sum = SEV.reduce((a,k)=>a+c[k],0);
        if (sum > 0) return c;
      }
      // 3) by_tool aggregation (common shape)
      if (j && j.by_tool && typeof j.by_tool === "object") {
        const c = ZERO();
        for (const k of Object.keys(j.by_tool)) {
          const t = j.by_tool[k];
          if (!t || typeof t !== "object") continue;
          if (t.counts_by_severity && typeof t.counts_by_severity === "object") addCounts(c, t.counts_by_severity);
          else if (t.counts && typeof t.counts === "object") addCounts(c, t.counts);
          else if (t.severity && typeof t.severity === "object") addCounts(c, t.severity);
        }
        const sum = SEV.reduce((a,k)=>a+c[k],0);
        if (sum > 0) return c;
      }
      return null;
    };

    const isTarget = (u) => {
      if (!u) return false;
      const s = String(u);
      if (!s.includes("/api/vsp/run_file_allow")) return false;
      if (s.includes("path=run_gate_summary.json")) return true;
      if (s.includes("path=run_gate.json")) return true;
      return false;
    };

    const getRid = (u) => {
      try { return (new URL(u, window.location.origin)).searchParams.get("rid") || ""; }
      catch(_) { return ""; }
    };

    const prevFetch = window.fetch ? window.fetch.bind(window) : null;
    if (!prevFetch) return;

    window.fetch = async (input, init) => {
      const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
      const resp = await prevFetch(input, init);
      if (!isTarget(url)) return resp;

      try {
        const txt = await resp.clone().text();
        let j = null;
        try { j = JSON.parse(txt); } catch(_e) { return resp; }
        if (!j || typeof j !== "object") return resp;

        if (!("ok" in j)) j.ok = true;

        const rid = getRid(url);
        if (rid) {
          if (!("rid" in j)) j.rid = rid;
          if (!("run_id" in j)) j.run_id = rid;
        }

        // ensure KPI-friendly counts
        const c = tryExtractCounts(j);
        if (c) {
          j.meta = (j.meta && typeof j.meta === "object") ? j.meta : {};
          if (!j.meta.counts_by_severity) j.meta.counts_by_severity = c;
          if (!j.counts_by_severity) j.counts_by_severity = c;
        }

        // debug hook
        window.__vsp_last_gate_summary = j;

        const h = new Headers(resp.headers || {});
        h.set("content-type", "application/json");
        return new Response(JSON.stringify(j), { status: resp.status, headers: h });
      } catch (e) {
        try { console.warn("[VSP][rungate_ok_norm_v2] error:", e); } catch(_){}
        return resp;
      }
    };

    try { console.log("[VSP] run_gate_summary ok-normalize v2 enabled"); } catch(_){}
  } catch(_e) {}
})();
/* ===================== /VSP_P1_RUN_GATE_SUMMARY_OK_NORMALIZE_V2 ===================== */
"""

p.write_text(patch + "\n" + s, encoding="utf-8")
print("[OK] patched:", p)
PY

command -v node >/dev/null 2>&1 && node --check "$JS" && echo "[OK] node --check passed" || true
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] run_gate_summary ok-normalize v2 patch applied."
