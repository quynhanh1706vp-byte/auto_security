#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date; need sed; need grep

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_nospam_${TS}"
echo "[BACKUP] ${JS}.bak_nospam_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_CLIENT_RUNFILEALLOW_FALLBACK_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

helper = textwrap.dedent(r"""
/* ===================== VSP_P1_CLIENT_RUNFILEALLOW_FALLBACK_V1 =====================
   Commercial UX: fallback reports/<file> <-> <file> for run_file_allow; no console spam.
================================================================================== */
window.__vsp_runfileallow_fetch_v1 = window.__vsp_runfileallow_fetch_v1 || (async function(opts){
  // opts: { base, rid, path, acceptJson=true }
  const base = (opts && opts.base) || "";
  const rid  = (opts && opts.rid)  || "";
  const path = (opts && opts.path) || "";
  const acceptJson = (opts && opts.acceptJson) !== false;

  const norm = (x)=> (x||"").replace(/\\/g,"/").replace(/^\/+/,"");
  const p0 = norm(path);

  // Build fallback candidates:
  // - if reports/... then try root
  // - else try reports/...
  const cands = [p0];
  if (p0.startsWith("reports/")) cands.push(p0.slice("reports/".length));
  else cands.push("reports/" + p0);

  // de-dupe
  const uniq = [];
  for (const c of cands) if (c && !uniq.includes(c)) uniq.push(c);

  const mk = (pp)=> `${base}/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(pp)}`;

  let lastErr = null;
  for (const pp of uniq){
    try{
      const r = await fetch(mk(pp), { credentials:"same-origin" });
      if (!r.ok) { lastErr = new Error(`HTTP ${r.status} for ${pp}`); continue; }
      if (!acceptJson) return { ok:true, path:pp, resp:r, data:null };
      const ct = (r.headers.get("content-type")||"").toLowerCase();
      if (ct.includes("application/json")) return { ok:true, path:pp, resp:r, data: await r.json() };
      // if server returns json-as-text, try parse
      const tx = await r.text();
      try { return { ok:true, path:pp, resp:r, data: JSON.parse(tx) }; } catch(e){ return { ok:true, path:pp, resp:r, data: tx }; }
    }catch(e){
      lastErr = e;
    }
  }
  return { ok:false, err: (lastErr && (lastErr.message||String(lastErr))) || "fetch failed", tried: uniq };
});

window.__vsp_badge_degraded_v1 = window.__vsp_badge_degraded_v1 || (function(msg){
  try{
    const id = "vsp_degraded_badge_v1";
    let el = document.getElementById(id);
    if (!el){
      el = document.createElement("div");
      el.id = id;
      el.style.cssText = "position:fixed;right:12px;bottom:12px;z-index:9999;background:#2a0f12;border:1px solid #7a2a33;color:#ffb3bd;padding:8px 10px;border-radius:10px;font:12px/1.3 system-ui,Segoe UI,Arial;box-shadow:0 10px 30px rgba(0,0,0,.35);max-width:360px";
      document.body.appendChild(el);
    }
    el.textContent = msg || "DEGRADED: missing artifact";
    clearTimeout(window.__vsp_degraded_badge_t);
    window.__vsp_degraded_badge_t = setTimeout(()=>{ try{ el.remove(); }catch(e){} }, 6500);
  }catch(e){}
});

/* Soft-wrap fetch calls to run_file_allow for core artifacts */
window.__vsp_runfileallow_softwrap_v1 = window.__vsp_runfileallow_softwrap_v1 || (function(){
  if (window.__vsp_runfileallow_softwrap_v1_done) return;
  window.__vsp_runfileallow_softwrap_v1_done = true;

  const origFetch = window.fetch;
  window.fetch = async function(input, init){
    try{
      const url = (typeof input === "string") ? input : (input && input.url) || "";
      if (url.includes("/api/vsp/run_file_allow?") && url.includes("path=")){
        // Only apply to the 4 files we care about most (avoid breaking other exports)
        const u = new URL(url, window.location.origin);
        const rid = u.searchParams.get("rid") || "";
        const path = u.searchParams.get("path") || "";
        const p = (path||"").replace(/\\/g,"/").replace(/^\/+/,"");

        const core = new Set([
          "run_gate_summary.json","reports/run_gate_summary.json",
          "run_gate.json","reports/run_gate.json",
        ]);

        if (core.has(p)){
          const res = await window.__vsp_runfileallow_fetch_v1({ base:"", rid, path:p, acceptJson:false });
          if (res && res.ok && res.resp) return res.resp;
          // degrade silently, return original fetch result (may be 403/404) but without throwing
          try{ window.__vsp_badge_degraded_v1(`DEGRADED: cannot load ${p} (${(res&&res.err)||"err"})`); }catch(e){}
          return origFetch.apply(this, arguments);
        }
      }
    }catch(e){
      // no spam
    }
    return origFetch.apply(this, arguments);
  };
})();
""").strip("\n") + "\n"

# Inject near the top after the first IIFE/opening marker, else prepend
ins_at = s.find("(()=>")
if ins_at != -1:
    # insert after first opening line end
    nl = s.find("\n", ins_at)
    if nl == -1: nl = 0
    s2 = s[:nl+1] + helper + s[nl+1:]
else:
    s2 = helper + "\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

node --check "$JS"
echo "[OK] node --check"
