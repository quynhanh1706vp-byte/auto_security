#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

TS=time.strftime("%Y%m%d_%H%M%S")

CLEAN = r'''<!-- VSP_P0_RUNS_FETCH_LOCK_V1 -->
<script id="VSP_P0_RUNS_FETCH_LOCK_V1">
(()=> {
  if (window.__vsp_p0_runs_fetch_lock_v1) return;
  window.__vsp_p0_runs_fetch_lock_v1 = true;

  // clear stale persisted RUNS fail flags to stop boot-flicker
  try{
    const ks = Object.keys(localStorage || {});
    for (const k of ks){
      if (/runs/i.test(k) && /(fail|degrad|503|error)/i.test(k)) localStorage.removeItem(k);
      if (/vsp_?runs/i.test(k) && /(fail|degrad|503|error)/i.test(k)) localStorage.removeItem(k);
      if (/VSP/i.test(k) && /(RUNS).*?(FAIL|503|DEGRA)/i.test(k)) localStorage.removeItem(k);
    }
  }catch(_){}

  const orig = (window.fetch && window.fetch.bind) ? window.fetch.bind(window) : null;
  if (!orig) return;

  const CACHE_KEY = "vsp_runs_cache_last_ok";

  const mkResp = (obj, degraded) => {
    const headers = new Headers({
      "Content-Type":"application/json; charset=utf-8",
      "Cache-Control":"no-store",
      "X-VSP-Degraded": String(degraded ? 1 : 0),
      "X-VSP-Fix": "runs_fetch_lock_v1"
    });
    return new Response(JSON.stringify(obj), { status: 200, headers });
  };

  const isRuns = (u) => !!u && (String(u).includes("/api/vsp/runs"));

  async function wrapRuns(input, init){
    let url = "";
    try{ url = (typeof input === "string") ? input : (input && input.url) ? input.url : ""; }catch(_){}
    if (!isRuns(url)) return orig(input, init);

    try{
      const r = await orig(input, init);

      // if OK -> cache last-good
      if (r && r.ok){
        try{
          const j = await r.clone().json();
          if (j && typeof j === "object"){
            j.ok = true;
            localStorage.setItem(CACHE_KEY, JSON.stringify(j));
          }
        }catch(_){}
        return r;
      }

      // non-OK -> try json then force 200 + ok=true
      let j = null;
      try{ j = r ? await r.clone().json() : null; }catch(_){}
      if (j && typeof j === "object"){
        j.ok = true;
        j._degraded = true;
        j._orig_status = r ? r.status : 0;
        try{ localStorage.setItem(CACHE_KEY, JSON.stringify(j)); }catch(_){}
        return mkResp(j, true);
      }

      // fallback to cached last-ok
      let cached = null;
      try{ cached = JSON.parse(localStorage.getItem(CACHE_KEY) || "null"); }catch(_){}
      const payload = cached || {ok:true,_degraded:true,_orig_status:(r?r.status:0),items:[],note:"runs-fallback(nojson)"};
      return mkResp(payload, true);

    }catch(_e){
      let cached = null;
      try{ cached = JSON.parse(localStorage.getItem(CACHE_KEY) || "null"); }catch(_){}
      const payload = cached || {ok:true,_degraded:true,_orig_status:0,items:[],note:"runs-fallback(exception)"};
      return mkResp(payload, true);
    }
  }

  // lock fetch (prevent later overrides)
  try{
    Object.defineProperty(window, "fetch", { value: wrapRuns, writable:false, configurable:false });
  }catch(_){
    window.fetch = wrapRuns;
  }
  console.log("[VSP][P0] runs fetch lock installed");
})();
</script>
'''

tpls = list(Path("templates").glob("*.html"))
changed = 0

pat = re.compile(r'<script\s+id="VSP_P0_RUNS_FETCH_LOCK_V1"[^>]*>.*?</script>', re.S|re.I)

for p in tpls:
    s = p.read_text(encoding="utf-8", errors="replace")
    if "VSP_P0_RUNS_FETCH_LOCK_V1" not in s:
        continue

    bak = p.with_name(p.name + f".bak_fix_runslock_js_{TS}")
    bak.write_text(s, encoding="utf-8")

    # replace ALL occurrences of the script block (important: you have it twice -> vsp5:183 and vsp5:715)
    s2, n = pat.subn(CLEAN, s)
    if n == 0:
        # if malformed, do a broader cleanup: remove any line containing the id then insert clean in <head>
        s2 = re.sub(r'^.*VSP_P0_RUNS_FETCH_LOCK_V1.*$\n?', '', s, flags=re.M)
        m = re.search(r"<head[^>]*>", s2, flags=re.I)
        if m:
            s2 = s2[:m.end()] + "\n" + CLEAN + "\n" + s2[m.end():]
        n = 1

    p.write_text(s2, encoding="utf-8")
    print(f"[OK] fixed runslock script in {p} (replaced_blocks={n})")
    changed += 1

print("[DONE] templates changed =", changed)
PY

# js syntax sanity (optional)
for f in static/js/vsp_bundle_commercial_v2.js static/js/vsp_runs_tab_resolved_v1.js static/js/vsp_app_entry_safe_v1.js; do
  [ -f "$f" ] || continue
  if command -v node >/dev/null 2>&1; then node --check "$f" && echo "[OK] node --check $f"; fi
done

echo "[NEXT] restart UI then Ctrl+F5 /vsp5 and /runs (or open Incognito)"
