#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_netguard_v7_${TS}"
echo "[BACKUP] ${F}.bak_netguard_v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_HTML_NETGUARD_P1_V7"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject_py = r'''
# ---- VSP_P1_HTML_NETGUARD_P1_V7 (commercial polish: stop /vsp5 poll spam) ----
try:
    import re as _re
    from flask import request as _request
except Exception:
    _re = None
    _request = None

_VSP_P1_NETGUARD_HTML = r"""
<!-- VSP_P1_NETGUARD_GLOBAL_V7 -->
<script id="VSP_P1_NETGUARD_GLOBAL_V7">
(()=> {
  if (window.__vsp_p1_netguard_global_v7) return;
  window.__vsp_p1_netguard_global_v7 = true;

  const HOLD_MS = 15000;
  let holdUntil = Date.now() + 2500; // grace on first load/restart

  // drop noisy poll logs (handles "%c" too)
  const DROP = [
    /\[VSP\]\s*poll down; backoff/i,
    /poll down; backoff/i,
    /Fetch failed loading/i,
    /ERR_CONNECTION/i,
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
  if (!window.__vsp_console_filtered_v7){
    window.__vsp_console_filtered_v7 = true;
    for (const k of ["log","info","warn","error"]){
      const orig = console[k].bind(console);
      console[k] = (...args)=>{ if (_dropArgs(args)) return; return orig(...args); };
    }
  }

  function _isApiVsp(u){ return !!u && u.includes("/api/vsp/"); }
  function _isPlaceholder(u){ return !!u && (u === "<URL>" || u.includes("<URL>")); }
  function _key(u){
    try{
      const uu = new URL(u, location.origin);
      return "vsp_api_cache_v7::" + uu.pathname + uu.search;
    }catch(_){
      return "vsp_api_cache_v7::" + String(u);
    }
  }
  function _load(u){
    try{ const raw = localStorage.getItem(_key(u)); return raw ? JSON.parse(raw) : null; }catch(_){ return null; }
  }
  function _save(u,obj){
    try{ localStorage.setItem(_key(u), JSON.stringify(obj)); }catch(_){}
  }
  function _resp(obj,hdr){
    const h = new Headers({"Content-Type":"application/json; charset=utf-8"});
    try{ if (hdr) for (const [k,v] of Object.entries(hdr)) h.set(k, String(v)); }catch(_){}
    return new Response(JSON.stringify(obj), {status:200, headers:h});
  }

  // fetch wrapper
  if (window.fetch && !window.__vsp_fetch_wrapped_v7){
    window.__vsp_fetch_wrapped_v7 = true;
    const orig = window.fetch.bind(window);
    window.fetch = async (input, init)=>{
      let u="";
      try{ u = (typeof input==="string") ? input : (input && input.url) ? input.url : ""; }catch(_){}
      if (_isPlaceholder(u)){
        return _resp({ok:false, note:"intercepted <URL>", marker:"V7"}, {"X-VSP-Intercept":"1"});
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

  // XHR wrapper (stop DevTools spam)
  if (window.XMLHttpRequest && !window.__vsp_xhr_wrapped_v7){
    window.__vsp_xhr_wrapped_v7 = true;
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
          const cached = _isPlaceholder(u) ? {ok:false, note:"intercepted <URL>", marker:"V7"} : (_load(u) || {ok:false, note:"degraded-cache-empty"});
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
          return; // NO NETWORK
        }
      }
      return _send.apply(this, arguments);
    };
  }
})();
</script>
'''

# Insert an after_request hook safely at EOF
patch = f"\n\n# {MARK}\ntry:\n    _app = application\n    @_app.after_request\n    def _vsp_p1_html_netguard_v7(resp):\n        try:\n            if _request is None or _re is None:\n                return resp\n            if _request.path not in ('/vsp5','/vsp5/'):\n                return resp\n            ct = (resp.headers.get('Content-Type','') or '')\n            if 'text/html' not in ct:\n                return resp\n            html = resp.get_data(as_text=True)\n            if 'VSP_P1_NETGUARD_GLOBAL_V7' in html:\n                return resp\n            m = _re.search(r'<head[^>]*>', html, flags=_re.I)\n            if not m:\n                return resp\n            ins = m.end()\n            html2 = html[:ins] + '\\n' + {inject_py!r}.split('\\n',1)[1] + '\\n' + html[ins:]\n            resp.set_data(html2)\n            resp.headers['Content-Length'] = str(len(resp.get_data()))\n            return resp\n        except Exception:\n            return resp\nexcept Exception:\n    pass\n"

# The trick: inject_py already contains the HTML <script>, but we want only the HTML string, not python.
# So we embed inject_py text and split from first newline to drop the leading comment line.
# (keeps it self-contained)
s2 = s + patch.replace({inject_py!r}, repr(inject_py))

p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

sudo systemctl restart vsp-ui-8910.service
echo "[OK] restarted vsp-ui-8910.service"

echo "[DONE] V7 applied"
