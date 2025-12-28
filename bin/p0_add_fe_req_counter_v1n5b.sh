#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || err "missing $JS"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_reqcount_v1n5b_${TS}"
ok "backup: ${JS}.bak_reqcount_v1n5b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_FE_REQ_COUNTER_V1N5B"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject=r'''/* ===================== VSP_P0_FE_REQ_COUNTER_V1N5B =====================
   Lightweight request telemetry for commercial audit (no server access log needed).
   Use in DevTools console:
     __vspReqTop(10)  // top endpoints in last 10 seconds
     __vspReqClear()
============================================================================ */
(function(){
  try{
    if (window.__VSP_REQ_COUNTER_V1N5B__) return;
    window.__VSP_REQ_COUNTER_V1N5B__ = true;

    window.__VSP_REQ_LOG = window.__VSP_REQ_LOG || [];
    function norm(u){
      try{
        const x = new URL(String(u), location.origin);
        if (x.origin !== location.origin) return null;
        if (!x.pathname.startsWith("/api/vsp/")) return null;
        x.searchParams.delete("ts"); x.searchParams.delete("_ts"); x.searchParams.delete("__ts");
        // keep rid but normalize ordering
        const keys = Array.from(x.searchParams.keys()).sort();
        const pairs=[];
        for(const k of keys){
          const vals=x.searchParams.getAll(k);
          for(const v of vals) pairs.push([k,v]);
        }
        x.search="";
        for(const [k,v] of pairs) x.searchParams.append(k,v);
        return x.pathname + (x.search?x.search:"");
      }catch(e){ return null; }
    }

    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (!_fetch) return;

    window.fetch = function(input, init){
      try{
        const method = ((init&&init.method)?String(init.method):"GET").toUpperCase();
        const key = norm(input);
        if (key){
          window.__VSP_REQ_LOG.push({ t: Date.now(), m: method, u: key });
          // cap memory
          if (window.__VSP_REQ_LOG.length > 2000) window.__VSP_REQ_LOG.splice(0, 500);
        }
      }catch(e){}
      return _fetch(input, init);
    };

    window.__vspReqClear = function(){ try{ window.__VSP_REQ_LOG = []; }catch(e){} };

    window.__vspReqTop = function(seconds){
      try{
        const sec = Math.max(1, Number(seconds||10));
        const cut = Date.now() - sec*1000;
        const arr = (window.__VSP_REQ_LOG||[]).filter(x=>x && x.t>=cut);
        const m = new Map();
        for(const x of arr){
          const k = x.u;
          m.set(k, (m.get(k)||0)+1);
        }
        const out = Array.from(m.entries()).sort((a,b)=>b[1]-a[1]).slice(0,25);
        console.log("[VSP_REQ_TOP]", { window_sec: sec, total: arr.length });
        for(const [k,c] of out) console.log(String(c).padStart(4," "), k);
        return out;
      }catch(e){
        console.warn("[VSP_REQ_TOP] error", e);
        return [];
      }
    };

  }catch(e){}
})(); 
/* ===================== /VSP_P0_FE_REQ_COUNTER_V1N5B ===================== */'''

# inject right after the V1N5 block end to keep ordering stable
m=re.search(r'/\* ===================== /VSP_P0_GLOBAL_FETCH_CACHE_DEDUPE_V1N5 .*?\*/', s, flags=re.S)
if m:
    s2 = s[:m.end()] + "\n\n" + inject + "\n\n" + s[m.end():]
else:
    s2 = inject + "\n\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] injected", MARK)
PY

node --check "$JS" && ok "node --check OK: $JS" || { warn "node --check FAIL: rollback"; cp -f "${JS}.bak_reqcount_v1n5b_${TS}" "$JS"; err "rolled back"; }

echo "== [DONE] Reload /vsp5 then open DevTools Console and run: __vspReqTop(10) =="
