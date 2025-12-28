#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v node >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_relfetchxhr_${TS}"
echo "[BACKUP] ${JS}.bak_relfetchxhr_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_XHR_FETCH_NORMALIZE_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

hook = textwrap.dedent(r"""
/* ===================== VSP_P1_RELEASE_XHR_FETCH_NORMALIZE_V2 ===================== */
(()=> {
  if (window.__vsp_p1_release_xhr_fetch_norm_v2) return;
  window.__vsp_p1_release_xhr_fetch_norm_v2 = true;

  function isRel(u){
    try { return String(u||"").indexOf("/api/vsp/release_latest") !== -1; }
    catch(e){ return false; }
  }
  function normalize(j){
    try{
      if (!j || typeof j !== "object") return j;
      const st = String(j.release_status||"").toUpperCase();
      const ex = (j.release_pkg_exists === true);
      const pkg = (j.release_pkg || j.package || "").toString();
      if ((st === "OK" || ex) && pkg){
        j.ok = true;
        if (!j.package) j.package = pkg;
      }
      if (typeof j.ok !== "boolean") j.ok = true;
      return j;
    }catch(e){ return j; }
  }

  // fetch normalize (in case some parts use fetch)
  const _fetch = window.fetch;
  if (typeof _fetch === "function"){
    window.fetch = async function(input, init){
      const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
      const res = await _fetch.apply(this, arguments);
      try{
        if (!isRel(url)) return res;
        const clone = res.clone();
        const j = await clone.json().catch(()=>null);
        if (!j) return res;
        const body = JSON.stringify(normalize(j));
        return new Response(body, { status: res.status, statusText: res.statusText, headers: res.headers });
      }catch(e){
        return res;
      }
    };
  }

  // XHR normalize (covers axios/jquery/etc using XHR under the hood)
  const XHR = window.XMLHttpRequest;
  if (typeof XHR === "function" && XHR.prototype){
    const _open = XHR.prototype.open;
    const _send = XHR.prototype.send;

    XHR.prototype.open = function(method, url){
      try { this.__vsp_rel_url = url; } catch(e){}
      return _open.apply(this, arguments);
    };

    XHR.prototype.send = function(){
      try{
        this.addEventListener("readystatechange", function(){
          try{
            if (this.readyState !== 4) return;
            const url = this.__vsp_rel_url || "";
            if (!isRel(url)) return;

            // only if JSON-ish response
            const ct = (this.getResponseHeader && this.getResponseHeader("content-type")) ? this.getResponseHeader("content-type") : "";
            if (ct && ct.indexOf("application/json") === -1 && ct.indexOf("text/json") === -1 && ct.indexOf("json") === -1) return;

            // responseText is read-only; we patch by defining getter returning normalized text
            const raw = this.responseText;
            let j = null;
            try { j = JSON.parse(raw); } catch(e){ return; }
            const norm = JSON.stringify(normalize(j));

            // override responseText/response with getters
            Object.defineProperty(this, "responseText", { get: ()=> norm });
            Object.defineProperty(this, "response", { get: ()=> norm });
          }catch(e){}
        }, false);
      }catch(e){}
      return _send.apply(this, arguments);
    };
  }
})();
/* ===================== /VSP_P1_RELEASE_XHR_FETCH_NORMALIZE_V2 ===================== */
""")

p.write_text(s.rstrip() + "\n\n" + hook + "\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] release XHR+fetch normalize v2 installed."
