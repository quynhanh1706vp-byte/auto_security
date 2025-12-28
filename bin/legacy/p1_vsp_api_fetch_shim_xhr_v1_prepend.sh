#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fetchshim_${TS}"
echo "[BACKUP] ${JS}.bak_fetchshim_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_API_FETCH_SHIM_XHR_V1"
if marker in s:
    print("[OK] already applied:", marker)
    raise SystemExit(0)

shim = textwrap.dedent(r"""
/* ===================== VSP_P1_API_FETCH_SHIM_XHR_V1 =====================
   Commercial hardening:
   - Bypass global fetch wrappers for /api/vsp/* using XHR (no "body stream already read")
   - Provide compat for /api/vsp/rid_latest_gate_root by deriving from /api/vsp/runs?limit=1
   - Return Response-like object with cached body (text/json can be called multiple times)
========================================================================= */
(()=> {
  if (window.__vsp_api_fetch_shim_xhr_v1) return;
  window.__vsp_api_fetch_shim_xhr_v1 = true;

  const ORIG_FETCH = window.fetch ? window.fetch.bind(window) : null;

  function absUrl(u){
    try{
      if (typeof u !== "string") return null;
      if (u.startsWith("http://") || u.startsWith("https://")) return u;
      if (u.startsWith("/")) return location.origin + u;
      return location.origin + "/" + u;
    }catch(e){ return null; }
  }
  function isVspApi(u){
    if (typeof u !== "string") return false;
    return u.includes("/api/vsp/");
  }
  function xhrText(url){
    return new Promise((resolve,reject)=>{
      const x = new XMLHttpRequest();
      x.open("GET", url, true);
      x.responseType = "text";
      x.withCredentials = true;
      x.onreadystatechange = ()=>{
        if (x.readyState !== 4) return;
        if (x.status < 200 || x.status >= 300) return reject(new Error("HTTP "+x.status));
        resolve(x.responseText || "");
      };
      x.onerror = ()=> reject(new Error("XHR error"));
      x.send();
    });
  }
  function mkResp(bodyText, status=200, statusText="OK", headersObj=null){
    const _t = String(bodyText ?? "");
    const _h = new Headers(headersObj || {"content-type":"application/json"});
    return {
      ok: status>=200 && status<300,
      status, statusText,
      headers: _h,
      // IMPORTANT: can be called multiple times
      text: async ()=> _t,
      json: async ()=> JSON.parse(_t),
      clone: ()=> mkResp(_t, status, statusText, Object.fromEntries(_h.entries()))
    };
  }

  function findRIDDeep(obj, depth=0){
    if (depth>7) return null;
    const RID_RE  = /\bVSP_[A-Z0-9_]*RUN_\d{8}_\d{6}\b/;
    const RID_RE2 = /\bRUN_\d{8}_\d{6}\b/;
    if (typeof obj === "string"){
      const m=obj.match(RID_RE); if (m) return m[0];
      const m2=obj.match(RID_RE2); if (m2) return m2[0];
      return null;
    }
    if (!obj || typeof obj!=="object") return null;
    if (Array.isArray(obj)){
      for (const x of obj){ const r=findRIDDeep(x, depth+1); if (r) return r; }
      return null;
    }
    for (const k of Object.keys(obj)){
      const r=findRIDDeep(obj[k], depth+1);
      if (r) return r;
    }
    return null;
  }

  async function compatRidLatestGateRoot(){
    // Derive "latest gate root" from runs API (works even if /rid_latest_gate_root is missing)
    const u = absUrl("/api/vsp/runs?limit=1&offset=0");
    const txt = await xhrText(u);
    let rid = null;
    try{
      const j = JSON.parse(txt);
      rid = findRIDDeep(j);
    }catch(e){
      // fallback regex on raw
      const m = txt.match(/\bVSP_[A-Z0-9_]*RUN_\d{8}_\d{6}\b/) or None
    }
    if (!rid){
      // raw regex scan
      const m = txt.match(/\bVSP_[A-Z0-9_]*RUN_\d{8}_\d{6}\b/);
      if (m) rid = m[0];
      else {
        const m2 = txt.match(/\bRUN_\d{8}_\d{6}\b/);
        if (m2) rid = m2[0];
      }
    }
    return { ok: !!rid, rid: rid, source: "runs?limit=1" };
  }

  window.fetch = async function(input, init){
    try{
      const url = (typeof input === "string") ? input : (input && input.url) ? String(input.url) : null;
      if (!url || !isVspApi(url)) return ORIG_FETCH ? ORIG_FETCH(input, init) : Promise.reject(new Error("fetch unavailable"));

      const full = absUrl(url) || url;

      // compat endpoint: rid_latest_gate_root
      if (full.includes("/api/vsp/rid_latest_gate_root")){
        const obj = await compatRidLatestGateRoot();
        return mkResp(JSON.stringify(obj), obj.ok ? 200 : 404, obj.ok ? "OK" : "NOT_FOUND");
      }

      // normal /api/vsp/*: XHR bypass
      const txt = await xhrText(full);
      // If server returns non-JSON, still allow text()
      try{
        JSON.parse(txt);
        return mkResp(txt, 200, "OK");
      }catch(e){
        return mkResp(txt, 200, "OK", {"content-type":"text/plain"});
      }
    }catch(e){
      // fallback to original fetch
      return ORIG_FETCH ? ORIG_FETCH(input, init) : Promise.reject(e);
    }
  };

  console.log("[VSP][FetchShimXHRV1] installed (intercept /api/vsp/* ; compat rid_latest_gate_root)");
})();
 /* ===================== /VSP_P1_API_FETCH_SHIM_XHR_V1 ===================== */
""").lstrip("\n")

# Tiny fix: python doesn't support "or None" in JS snippet above. Replace that line safely.
shim = shim.replace('const m = txt.match(/\\bVSP_[A-Z0-9_]*RUN_\\d{8}_\\d{6}\\b/) or None',
                    '/* js */')

p.write_text(shim + "\n\n" + s, encoding="utf-8")
print("[OK] prepended:", marker)
PY

echo "[DONE] FetchShimXHRV1 prepended."
echo "Next: restart UI then HARD refresh /vsp5 (Ctrl+Shift+R)."
