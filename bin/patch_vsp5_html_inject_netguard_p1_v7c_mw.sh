#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_netguard_v7c_${TS}"
echo "[BACKUP] ${F}.bak_netguard_v7c_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_HTML_NETGUARD_P1_V7C_MW"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r'''
# ---- VSP_P1_HTML_NETGUARD_P1_V7C_MW (wrap WSGI application; always inject on /vsp5) ----
try:
    import re as _re
except Exception:
    _re = None

_VSP_P1_NETGUARD_HTML_V7C = r"""
<!-- VSP_P1_NETGUARD_GLOBAL_V7C -->
<script id="VSP_P1_NETGUARD_GLOBAL_V7C">
(()=> {
  if (window.__vsp_p1_netguard_global_v7c) return;
  window.__vsp_p1_netguard_global_v7c = true;

  const HOLD_MS = 15000;
  let holdUntil = Date.now() + 2500;

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
  if (!window.__vsp_console_filtered_v7c){
    window.__vsp_console_filtered_v7c = true;
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
      return "vsp_api_cache_v7c::" + uu.pathname + uu.search;
    }catch(_){
      return "vsp_api_cache_v7c::" + String(u);
    }
  }
  function _load(u){ try{ const raw=localStorage.getItem(_cacheKey(u)); return raw?JSON.parse(raw):null; }catch(_){ return null; } }
  function _save(u,obj){ try{ localStorage.setItem(_cacheKey(u), JSON.stringify(obj)); }catch(_){ } }
  function _resp(obj,hdr){
    const h = new Headers({"Content-Type":"application/json; charset=utf-8"});
    try{ if (hdr) for (const [k,v] of Object.entries(hdr)) h.set(k, String(v)); }catch(_){}
    return new Response(JSON.stringify(obj), {status:200, headers:h});
  }

  if (window.fetch && !window.__vsp_fetch_wrapped_v7c){
    window.__vsp_fetch_wrapped_v7c = true;
    const orig = window.fetch.bind(window);
    window.fetch = async (input, init)=>{
      let u="";
      try{ u = (typeof input==="string") ? input : (input && input.url) ? input.url : ""; }catch(_){}
      if (_isPlaceholder(u)) return _resp({ok:false, note:"intercepted <URL>", marker:"V7C"}, {"X-VSP-Intercept":"1"});
      if (_isApiVsp(u)){
        const now = Date.now();
        if (now < holdUntil){
          const cached = _load(u) || {ok:false, note:"degraded-cache-empty"};
          return _resp(cached, {"X-VSP-Hold":"1","X-VSP-Cache":"1"});
        }
        try{
          const r = await orig(input, init);
          if (r && r.ok){
            try{ const j = await r.clone().json(); if (j && typeof j==="object") _save(u,j); }catch(_){}
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

  if (window.XMLHttpRequest && !window.__vsp_xhr_wrapped_v7c){
    window.__vsp_xhr_wrapped_v7c = true;
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
          const cached = _isPlaceholder(u) ? {ok:false, note:"intercepted <URL>", marker:"V7C"} : (_load(u) || {ok:false, note:"degraded-cache-empty"});
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
          return;
        }
      }
      return _send.apply(this, arguments);
    };
  }
})();
</script>
"""

def _vsp_p1_inject_head_v7c(body_bytes: bytes) -> bytes:
    if _re is None:
        return body_bytes
    try:
        html = body_bytes.decode("utf-8", errors="replace")
    except Exception:
        return body_bytes
    if "VSP_P1_NETGUARD_GLOBAL_V7C" in html:
        return body_bytes
    m = _re.search(r"<head[^>]*>", html, flags=_re.I)
    if not m:
        return body_bytes
    ins = m.end()
    html2 = html[:ins] + "\n" + _VSP_P1_NETGUARD_HTML_V7C + "\n" + html[ins:]
    return html2.encode("utf-8", errors="replace")

class _VSP_HTML_Injector_V7C:
    __vsp_wrapped_v7c__ = True
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path not in ("/vsp5", "/vsp5/"):
            return self.app(environ, start_response)

        captured = {}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc_info"] = exc_info
            # delay calling real start_response until body possibly modified
            return None

        result = self.app(environ, _sr)
        try:
            body = b"".join(result) if result is not None else b""
        finally:
            try:
                if hasattr(result, "close"):
                    result.close()
            except Exception:
                pass

        status = captured.get("status", "200 OK")
        headers = captured.get("headers", [])

        # check content-type
        ct = ""
        for k, v in headers:
            if str(k).lower() == "content-type":
                ct = str(v)
                break

        if "text/html" in (ct or ""):
            body2 = _vsp_p1_inject_head_v7c(body)
            if body2 != body:
                body = body2
                # fix content-length
                new_headers = []
                for k, v in headers:
                    if str(k).lower() == "content-length":
                        continue
                    new_headers.append((k, v))
                new_headers.append(("Content-Length", str(len(body))))
                headers = new_headers

        start_response(status, headers, captured.get("exc_info"))
        return [body]

try:
    if not getattr(application, "__vsp_wrapped_v7c__", False):
        application = _VSP_HTML_Injector_V7C(application)
except Exception:
    pass
# ---- end VSP_P1_HTML_NETGUARD_P1_V7C_MW ----
'''

p.write_text(s.rstrip() + "\n\n# " + MARK + "\n" + block.lstrip() + "\n", encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK"
sudo systemctl restart vsp-ui-8910.service && echo "[OK] restarted: vsp-ui-8910.service"
echo "[DONE] V7C applied"
