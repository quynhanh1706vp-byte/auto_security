#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re

UI = Path(".").resolve()
tpl_dir = UI / "templates"
if not tpl_dir.is_dir():
    raise SystemExit("[ERR] templates/ not found")

# pick candidate templates that likely serve /vsp5
cands = []
for p in tpl_dir.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="replace")
    if ("SECURITY_BUNDLE" in s) or ("VersaSecure" in s) or ("/vsp5" in s) or ("Runs & Reports" in s):
        cands.append(p)

if not cands:
    # fallback: patch all html (safe with marker id)
    cands = list(tpl_dir.rglob("*.html"))

MARK = "VSP_P1_NETGUARD_GLOBAL_V6"
inject_js = r"""
<!-- VSP_P1_NETGUARD_GLOBAL_V6 -->
<script id="VSP_P1_NETGUARD_GLOBAL_V6">
(()=> {
  if (window.__vsp_p1_netguard_global_v6) return;
  window.__vsp_p1_netguard_global_v6 = true;

  const HOLD_MS = 15000;
  let holdUntil = 0;

  const DROP = [
    /\[VSP\]\s*poll down; backoff/i,
    /runs fetch guard\/backoff enabled/i,
    /VSP_ROUTE_GUARD_RUNS_ONLY_/i,
    /Fetch failed loading/i,
    /ERR_CONNECTION/i,
    /Fetch finished loading:\s*GET\s*"<URL>"/i
  ];

  function shouldDrop(args){
    try{
      const a0 = (args && args.length && typeof args[0]==="string") ? args[0] : "";
      return DROP.some(rx => rx.test(a0));
    }catch(_){ return false; }
  }

  // console filter (for inline poll logs on vsp5:390)
  if (!window.__vsp_console_filtered_v6){
    window.__vsp_console_filtered_v6 = true;
    for (const k of ["log","info","warn","error"]){
      const orig = console[k].bind(console);
      console[k] = (...args)=>{ if (shouldDrop(args)) return; return orig(...args); };
    }
  }

  function isApiVsp(u){
    if (!u) return false;
    return (u.includes("/api/vsp/"));
  }
  function isPlaceholder(u){
    if (!u) return false;
    return (u === "<URL>" || u.includes("<URL>"));
  }
  function cacheKey(u){
    // normalize: drop origin
    try{
      const uu = new URL(u, location.origin);
      return "vsp_api_cache_v6::" + (uu.pathname + (uu.search or ""));
    }catch(_){
      return "vsp_api_cache_v6::" + String(u);
    }
  }
  function loadCache(u){
    try{
      const raw = localStorage.getItem(cacheKey(u));
      if (!raw) return null;
      return JSON.parse(raw);
    }catch(_){ return null; }
  }
  function saveCache(u, obj){
    try{
      localStorage.setItem(cacheKey(u), JSON.stringify(obj));
    }catch(_){}
  }
  function respJson(obj, hdr){
    const h = new Headers({"Content-Type":"application/json; charset=utf-8"});
    try{ if (hdr) for (const [k,v] of Object.entries(hdr)) h.set(k, String(v)); }catch(_){}
    return new Response(JSON.stringify(obj), {status:200, headers:h});
  }

  // --- fetch wrapper
  if (window.fetch && !window.__vsp_fetch_wrapped_v6){
    window.__vsp_fetch_wrapped_v6 = true;
    const orig = window.fetch.bind(window);
    window.fetch = async (input, init)=>{
      let u="";
      try{ u = (typeof input==="string") ? input : (input && input.url) ? input.url : ""; }catch(_){}
      if (isPlaceholder(u)){
        return respJson({ok:false, note:"intercepted <URL>", marker:"V6"}, {"X-VSP-Intercept":"1"});
      }
      if (isApiVsp(u)){
        const now = Date.now();
        if (now < holdUntil){
          const cached = loadCache(u) || {ok:false, note:"degraded-cache-empty"};
          return respJson(cached, {"X-VSP-Hold":"1","X-VSP-Cache":"1"});
        }
        try{
          const r = await orig(input, init);
          if (r && r.ok){
            try{
              const j = await r.clone().json();
              if (j && typeof j==="object") saveCache(u, j);
            }catch(_){}
            return r;
          }
          holdUntil = Date.now() + HOLD_MS;
          const cached = loadCache(u) || {ok:false, note:"degraded-cache-empty"};
          return respJson(cached, {"X-VSP-Hold":"1","X-VSP-Cache":"1","X-VSP-Non200": r ? r.status : "NA"});
        }catch(_e){
          holdUntil = Date.now() + HOLD_MS;
          const cached = loadCache(u) || {ok:false, note:"degraded-cache-empty"};
          return respJson(cached, {"X-VSP-Hold":"1","X-VSP-Cache":"1","X-VSP-NetFail":"1"});
        }
      }
      return orig(input, init);
    };
  }

  // --- XHR wrapper (stops DevTools XHR spam)
  if (window.XMLHttpRequest && !window.__vsp_xhr_wrapped_v6){
    window.__vsp_xhr_wrapped_v6 = true;
    const _open = XMLHttpRequest.prototype.open;
    const _send = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url){
      try{ this.__vsp_url = String(url || ""); }catch(_){}
      return _open.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function(body){
      const u = (this && this.__vsp_url) ? String(this.__vsp_url) : "";
      if (isPlaceholder(u) || isApiVsp(u)){
        const now = Date.now();
        if (isPlaceholder(u) || (now < holdUntil && isApiVsp(u))){
          const cached = isPlaceholder(u) ? {ok:false, note:"intercepted <URL>", marker:"V6"} : (loadCache(u) || {ok:false, note:"degraded-cache-empty"});
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

          return; // IMPORTANT: no network
        }

        // attach cache+hold behavior
        const self=this;
        const onLoad = ()=>{
          try{
            if (self.status === 200){
              let j=null;
              try{ j = JSON.parse(self.responseText || "null"); }catch(_){}
              if (j && typeof j==="object") saveCache(u, j);
            }else{
              holdUntil = Date.now() + HOLD_MS;
            }
          }catch(_){}
        };
        const onErr = ()=>{ holdUntil = Date.now() + HOLD_MS; };
        try{ self.addEventListener("load", onLoad, {once:true}); }catch(_){}
        try{ self.addEventListener("error", onErr, {once:true}); }catch(_){}
        try{ self.addEventListener("timeout", onErr, {once:true}); }catch(_){}
      }
      return _send.apply(this, arguments);
    };
  }
})();
</script>
"""

patched = []
for tpl in cands:
    s = tpl.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        continue

    # inject right after <head ...>
    m = re.search(r"<head[^>]*>", s, flags=re.I)
    if not m:
        continue
    ins = m.end()
    out = s[:ins] + "\n" + inject_js.strip() + "\n" + s[ins:]
    bak = tpl.with_suffix(tpl.suffix + f".bak_p1v6_{Path().cwd().name}_{len(patched)}")
    # safer backup: timestamp in filename
    bak = tpl.with_name(tpl.name + f".bak_p1v6_{Path().cwd().name}")
    # ensure unique
    i=0
    while bak.exists():
        i += 1
        bak = tpl.with_name(tpl.name + f".bak_p1v6_{i}")
    bak.write_text(s, encoding="utf-8")
    tpl.write_text(out, encoding="utf-8")
    patched.append(str(tpl))

print("[OK] patched templates:", len(patched))
for x in patched[:20]:
    print(" -", x)
PY

# restart
if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --all | grep -q 'vsp-ui-8910.service'; then
  sudo systemctl restart vsp-ui-8910.service
  echo "[OK] restarted: vsp-ui-8910.service"
else
  echo "[NOTE] restart manually (no systemd unit detected)"
fi

echo "[DONE] VSP_P1_NETGUARD_GLOBAL_V6 injected"
