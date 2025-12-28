#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_netguard_v7b_${TS}"
echo "[BACKUP] ${F}.bak_netguard_v7b_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_HTML_NETGUARD_P1_V7B"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r'''
# ---- VSP_P1_HTML_NETGUARD_P1_V7B (commercial polish: stop /vsp5 poll spam) ----
try:
    import re as _re
    from flask import request as _request
except Exception:
    _re = None
    _request = None

_VSP_P1_NETGUARD_HTML_V7B = r"""
<!-- VSP_P1_NETGUARD_GLOBAL_V7B -->
<script id="VSP_P1_NETGUARD_GLOBAL_V7B">
(()=> {
  if (window.__vsp_p1_netguard_global_v7b) return;
  window.__vsp_p1_netguard_global_v7b = true;

  const HOLD_MS = 15000;
  let holdUntil = Date.now() + 2500; // grace on first load/restart

  // drop only noisy poll logs (do NOT hide real errors)
  const DROP = [
    /\[VSP\]\s*poll down; backoff/i,
    /poll down; backoff/i,
    /runs fetch guard\/backoff enabled/i,
    /VSP_ROUTE_GUARD_RUNS_ONLY_/i
  ];
  function _dropArgs(args){
    try{
      if (!args || !args.length) return false;
      const a0 = (typeof args[0] === "string") ? args[0] : "";
      return DROP.some(rx => rx.test(a0));
    }catch(_){ return false; }
  }
  if (!window.__vsp_console_filtered_v7b){
    window.__vsp_console_filtered_v7b = true;
    for (const k of ["log","info","warn","error"]){
      const orig = console[k].bind(console);
      console[k] = (...args)=>{ if (_dropArgs(args)) return; return orig(...args); };
    }
  }

  function _isApiVsp(u){ return !!u && u.includes("/api/vsp/"); }
  function _isPlaceholder(u){ return !!u && (u === "<URL>" || u.includes("<URL>")); }

  function _cacheKey(u){
    try{
      const uu = new URL(u, location.origin);
      return "vsp_api_cache_v7b::" + uu.pathname + uu.search;
    }catch(_){
      return "vsp_api_cache_v7b::" + String(u);
    }
  }
  function _load(u){
    try{
      const raw = localStorage.getItem(_cacheKey(u));
      return raw ? JSON.parse(raw) : null;
    }catch(_){ return null; }
  }
  function _save(u,obj){
    try{ localStorage.setItem(_cacheKey(u), JSON.stringify(obj)); }catch(_){}
  }
  function _resp(obj,hdr){
    const h = new Headers({"Content-Type":"application/json; charset=utf-8"});
    try{ if (hdr) for (const [k,v] of Object.entries(hdr)) h.set(k, String(v)); }catch(_){}
    return new Response(JSON.stringify(obj), {status:200, headers:h});
  }

  // fetch wrapper
  if (window.fetch && !window.__vsp_fetch_wrapped_v7b){
    window.__vsp_fetch_wrapped_v7b = true;
    const orig = window.fetch.bind(window);
    window.fetch = async (input, init)=>{
      let u="";
      try{ u = (typeof input==="string") ? input : (input && input.url) ? input.url : ""; }catch(_){}
      if (_isPlaceholder(u)){
        return _resp({ok:false, note:"intercepted <URL>", marker:"V7B"}, {"X-VSP-Intercept":"1"});
      }
      if (_isApiVsp(u)){
        const now = Date.now();
        if (now < holdUntil){
          const cached = _load(u) || {ok:false, note:"degraded-cache-empty"};
          return _resp(cached, {"X-VSP-Hold":"1","X-VSP-Cache":"1"});
        }
        try{
          const r = await orig(input, init);
          if (r && r.ok){
            try{
              const j = await r.clone().json();
              if (j && typeof j==="object") _save(u, j);
            }catch(_){}
            return r;
          }
          holdUntil = Date.now() + HOLD_MS;
          const cached = _load(u) || {ok:false, note:"degraded-cache-empty"};
          return _resp(cached, {"X-VSP-Hold":"1","X-VSP-Cache":"1","X-VSP-Non200": r ? r.status : "NA"});
        }catch(_e){
          holdUntil = Date.now() + HOLD_MS;
          const cached = _load(u) || {ok:false, note:"degraded-cache-empty"};
          return _resp(cached, {"X-VSP-Hold":"1","X-VSP-Cache":"1","X-VSP-NetFail":"1"});
        }
      }
      return orig(input, init);
    };
  }

  // XHR wrapper (stop DevTools spam during restart)
  if (window.XMLHttpRequest && !window.__vsp_xhr_wrapped_v7b){
    window.__vsp_xhr_wrapped_v7b = true;
    const _open = XMLHttpRequest.prototype.open;
    const _send = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url){
      try{ this.__vsp_url = String(url || ""); }catch(_){}
      return _open.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function(body){
      const u = (this && this.__vsp_url) ? String(this.__vsp_url) : "";
      if (_isPlaceholder(u) || _isApiVsp(u)){
        const now = Date.now();
        if (_isPlaceholder(u) || (now < holdUntil && _isApiVsp(u))){
          const cached = _isPlaceholder(u) ? {ok:false, note:"intercepted <URL>", marker:"V7B"} : (_load(u) || {ok:false, note:"degraded-cache-empty"});
          const txt = JSON.stringify(cached);
          try{
            Object.defineProperty(this, "status", { get: ()=>200, configurable:true });
            Object.defineProperty(this, "responseText", { get: ()=>txt, configurable:true });
            Object.defineProperty(this, "response", { get: ()=>txt, configurable:true });
          }catch(_){}
          const self=this;
          setTimeout(()=>{
            try{ if (typeof self.onreadystatechange==="function") self.onreadystatechange(); }catch(_){}
            try{ if (typeof self.onload==="function") self.onload(); }catch(_){}
            try{ self.dispatchEvent && self.dispatchEvent(new Event("load")); }catch(_){}
          },0);
          return; // NO NETWORK => no DevTools spam
        }
      }
      return _send.apply(this, arguments);
    };
  }
})();
</script>
"""

def _vsp_p1_inject_head_v7b(html: str) -> str:
    if _re is None:
        return html
    m = _re.search(r"<head[^>]*>", html, flags=_re.I)
    if not m:
        return html
    ins = m.end()
    return html[:ins] + "\n" + _VSP_P1_NETGUARD_HTML_V7B + "\n" + html[ins:]

try:
    _app = application  # must exist in this gateway
    @_app.after_request
    def _vsp_p1_html_netguard_v7b(resp):
        try:
            if _request is None or _re is None:
                return resp
            if _request.path not in ("/vsp5", "/vsp5/"):
                return resp
            ct = (resp.headers.get("Content-Type","") or "")
            if "text/html" not in ct:
                return resp
            html = resp.get_data(as_text=True)
            if "VSP_P1_NETGUARD_GLOBAL_V7B" in html:
                return resp
            html2 = _vsp_p1_inject_head_v7b(html)
            if html2 != html:
                resp.set_data(html2)
                resp.headers["Content-Length"] = str(len(resp.get_data()))
            return resp
        except Exception:
            return resp
except Exception:
    pass
# ---- end VSP_P1_HTML_NETGUARD_P1_V7B ----
'''

p.write_text(s.rstrip() + "\n\n" + block.lstrip() + "\n", encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
echo "[OK] restarted: vsp-ui-8910.service"
echo "[DONE] V7B applied"
