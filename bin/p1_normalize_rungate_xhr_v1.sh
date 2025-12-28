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
cp -f "$JS" "${JS}.bak_rungate_xhr_${TS}"
echo "[BACKUP] ${JS}.bak_rungate_xhr_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_XHR_RUNGATE_NORMALIZE_V1"
if MARK in s:
    print("[SKIP] marker already present:", MARK)
    raise SystemExit(0)

patch = r"""
/* ===================== VSP_P1_XHR_RUNGATE_NORMALIZE_V1 =====================
   Normalize run_gate_summary.json / run_gate.json for BOTH fetch + XMLHttpRequest.
   Fixes KPI stuck at "—" when UI expects ok:true / counts_by_severity.
============================================================================= */
(()=> {
  try {
    if (window.__vsp_p1_xhr_rungate_norm_v1) return;
    window.__vsp_p1_xhr_rungate_norm_v1 = true;

    const SEV = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const ZERO = ()=>({CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0});
    const addCounts = (dst, src) => {
      if (!src || typeof src !== "object") return dst;
      for (const k of SEV) dst[k] += Number(src[k]||0) || 0;
      return dst;
    };
    const tryExtractCounts = (j) => {
      if (j && typeof j.counts_total === "object") {
        const c = ZERO(); addCounts(c, j.counts_total);
        if (SEV.reduce((a,k)=>a+c[k],0) > 0) return c;
      }
      if (j && typeof j.counts_by_severity === "object") {
        const c = ZERO(); addCounts(c, j.counts_by_severity);
        if (SEV.reduce((a,k)=>a+c[k],0) > 0) return c;
      }
      if (j && j.by_tool && typeof j.by_tool === "object") {
        const c = ZERO();
        for (const tk of Object.keys(j.by_tool)) {
          const t = j.by_tool[tk];
          if (!t || typeof t !== "object") continue;
          if (t.counts_by_severity) addCounts(c, t.counts_by_severity);
          else if (t.counts) addCounts(c, t.counts);
          else if (t.severity) addCounts(c, t.severity);
        }
        if (SEV.reduce((a,k)=>a+c[k],0) > 0) return c;
      }
      return null;
    };

    const isTarget = (u) => {
      if (!u) return false;
      const s = String(u);
      return s.includes("/api/vsp/run_file_allow")
        && (s.includes("path=run_gate_summary.json") || s.includes("path=run_gate.json"));
    };
    const getRid = (u) => {
      try { return (new URL(u, location.origin)).searchParams.get("rid") || ""; }
      catch(_) { return ""; }
    };

    const normalize = (j, url) => {
      if (!j || typeof j !== "object") return j;
      if (!("ok" in j)) j.ok = true;

      const rid = getRid(url);
      if (rid) {
        if (!("rid" in j)) j.rid = rid;
        if (!("run_id" in j)) j.run_id = rid;
      }

      const c = tryExtractCounts(j);
      if (c) {
        j.meta = (j.meta && typeof j.meta === "object") ? j.meta : {};
        if (!j.meta.counts_by_severity) j.meta.counts_by_severity = c;
        if (!j.counts_by_severity) j.counts_by_severity = c;
      }

      window.__vsp_last_gate_summary = j;
      return j;
    };

    // ---- fetch path (keep, but stronger: ignore content-type)
    if (window.fetch && !window.__vsp_p1_fetch_rungate_norm_v1) {
      window.__vsp_p1_fetch_rungate_norm_v1 = true;
      const prevFetch = window.fetch.bind(window);
      window.fetch = async (input, init) => {
        const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
        const resp = await prevFetch(input, init);
        if (!isTarget(url)) return resp;
        try {
          const txt = await resp.clone().text();
          let j; try { j = JSON.parse(txt); } catch(_) { return resp; }
          j = normalize(j, url);
          const h = new Headers(resp.headers || {});
          h.set("content-type","application/json");
          console.warn("[VSP][norm] fetch normalized:", url);
          return new Response(JSON.stringify(j), {status: resp.status, headers: h});
        } catch(_) { return resp; }
      };
    }

    // ---- XHR path (axios)
    if (window.XMLHttpRequest && !window.__vsp_p1_xhr_hooked_v1) {
      window.__vsp_p1_xhr_hooked_v1 = true;
      const XHR = window.XMLHttpRequest;
      const _open = XHR.prototype.open;
      const _send = XHR.prototype.send;

      XHR.prototype.open = function(method, url) {
        try { this.__vsp_url = url; } catch(_) {}
        return _open.apply(this, arguments);
      };

      XHR.prototype.send = function() {
        try {
          const xhr = this;
          const url = xhr.__vsp_url || "";
          if (isTarget(url)) {
            xhr.addEventListener("readystatechange", function() {
              try {
                if (xhr.readyState !== 4) return;
                if (xhr.status !== 200) return;
                const txt = xhr.responseText;
                let j; try { j = JSON.parse(txt); } catch(_) { return; }
                j = normalize(j, url);
                const patched = JSON.stringify(j);

                // override responseText/response with patched payload if possible
                try {
                  Object.defineProperty(xhr, "responseText", { get: ()=>patched });
                } catch(_) {}
                try {
                  Object.defineProperty(xhr, "response", { get: ()=>patched });
                } catch(_) {}

                console.warn("[VSP][norm] XHR normalized:", url);
              } catch(_) {}
            }, false);
          }
        } catch(_) {}
        return _send.apply(this, arguments);
      };
    }

    console.log("[VSP] rungate normalize (fetch+XHR) enabled");
  } catch(e) {
    try { console.warn("[VSP] rungate normalize init error:", e); } catch(_){}
  }
})();
/* ===================== /VSP_P1_XHR_RUNGATE_NORMALIZE_V1 ===================== */
"""

p.write_text(patch + "\n" + s, encoding="utf-8")
print("[OK] patched:", p)
PY

command -v node >/dev/null 2>&1 && node --check "$JS" && echo "[OK] node --check passed" || true
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] XHR+fetch rungate normalize patch applied."
