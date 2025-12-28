#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

CAND_JS=(
  "static/js/vsp_bundle_commercial_v2.js"
  "static/js/vsp_bundle_commercial_v1.js"
  "static/js/vsp_runs_tab_resolved_v1.js"
  "static/js/vsp_app_entry_safe_v1.js"
)

python3 - <<'PY'
from pathlib import Path
import time

ts=time.strftime("%Y%m%d_%H%M%S")
MARK="VSP_P0_RUNS_FETCH_SHIM_DEFINITIVE_P0_V1"

shim = r"""
;(()=>{ // VSP_P0_RUNS_FETCH_SHIM_DEFINITIVE_P0_V1
  try{
    if (window.__VSP_P0_RUNS_FETCH_SHIM_DEFINITIVE_P0_V1) return;
    window.__VSP_P0_RUNS_FETCH_SHIM_DEFINITIVE_P0_V1 = true;

    const RUNS_RE = /\/api\/vsp\/runs(\?|$)/;
    const CACHE_KEY = "VSP_RUNS_CACHE_BODY_V1";
    const CACHE_TS  = "VSP_RUNS_CACHE_TS_V1";
    const MAX_AGE_MS = 10 * 60 * 1000; // 10 phút: đủ “dịu” để hết nhảy, vẫn không quá stale

    function now(){ return Date.now(); }
    function getCache(){
      try{
        const body = localStorage.getItem(CACHE_KEY);
        const ts   = parseInt(localStorage.getItem(CACHE_TS)||"0",10);
        if (!body) return null;
        if (!ts || (now()-ts)>MAX_AGE_MS) return null;
        return {body, ts};
      }catch(e){ return null; }
    }
    function putCache(body){
      try{
        localStorage.setItem(CACHE_KEY, body);
        localStorage.setItem(CACHE_TS, String(now()));
      }catch(e){}
    }
    function isRunsUrl(u){
      try{
        if (!u) return false;
        if (typeof u === "string") return RUNS_RE.test(u);
        if (u && typeof u.url === "string") return RUNS_RE.test(u.url);
      }catch(e){}
      return false;
    }

    const _fetch = window.fetch.bind(window);

    window.fetch = async function(input, init){
      const runs = isRunsUrl(input);
      if (!runs) return _fetch(input, init);

      // Luôn NO-STORE để tránh trạng thái “nhảy” do cache layer bất định
      const init2 = init ? {...init} : {};
      init2.cache = "no-store";

      try{
        const res = await _fetch(input, init2);

        // Nếu OK: cache body để dùng làm fallback cho lần sau
        if (res && res.ok){
          try{
            const clone = res.clone();
            const txt = await clone.text();
            // chỉ cache nếu có vẻ là JSON
            if (txt && (txt.trim().startsWith("{") || txt.trim().startsWith("["))){
              putCache(txt);
            }
          }catch(e){}
          return res;
        }

        // Nếu lỗi (503/500/timeout gateway…): trả về cache (HTTP 200) để UI không set FAIL
        const c = getCache();
        if (c && c.body){
          const headers = new Headers();
          headers.set("Content-Type","application/json; charset=utf-8");
          headers.set("Cache-Control","no-store");
          headers.set("X-VSP-DEGRADED","1");
          headers.set("X-VSP-RUNS-FALLBACK","1");
          return new Response(c.body, {status:200, headers});
        }

        // Không có cache thì trả nguyên trạng (để bạn vẫn nhìn thấy lỗi thật)
        return res;
      }catch(err){
        const c = getCache();
        if (c && c.body){
          const headers = new Headers();
          headers.set("Content-Type","application/json; charset=utf-8");
          headers.set("Cache-Control","no-store");
          headers.set("X-VSP-DEGRADED","1");
          headers.set("X-VSP-RUNS-FALLBACK","1");
          return new Response(c.body, {status:200, headers});
        }
        throw err;
      }
    };

    console.log("[VSP_RUNS] fetch shim enabled (definitive): cache+fallback for /api/vsp/runs*");
  }catch(e){
    console.warn("[VSP_RUNS] fetch shim init failed:", e);
  }
})();
"""

def patch_file(p: Path):
    if not p.exists(): return (False, f"[SKIP] missing: {p}")
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        return (False, f"[SKIP] already patched: {p}")
    # append shim near end to ensure it loads after other wrappers
    bak = p.with_name(p.name + f".bak_runs_shim_{ts}")
    bak.write_text(s, encoding="utf-8")
    s2 = s.rstrip() + "\n\n" + shim + "\n"
    p.write_text(s2, encoding="utf-8")
    return (True, f"[OK] injected: {p}  backup: {bak.name}")

changed=False
for rel in [
  "static/js/vsp_bundle_commercial_v2.js",
  "static/js/vsp_bundle_commercial_v1.js",
  "static/js/vsp_runs_tab_resolved_v1.js",
  "static/js/vsp_app_entry_safe_v1.js",
]:
    p=Path(rel)
    ok,msg=patch_file(p)
    print(msg)
    changed = changed or ok

print("[DONE] changed=", changed)
PY

# node syntax check (best-effort)
for f in "${CAND_JS[@]}"; do
  [ -f "$f" ] || continue
  if command -v node >/dev/null 2>&1; then
    node --check "$f" && echo "[OK] node --check: $f"
  fi
done

echo "[OK] Applied. Restart UI then Ctrl+F5 /runs"
