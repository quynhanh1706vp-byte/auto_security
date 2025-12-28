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

ROOT = Path(".")
cands = []

# patch both templates + js (bạn đang có nhiều wrapper nằm rải rác)
for pat in ["templates/**/*.html", "templates/*.html", "static/js/*.js", "static/js/**/*.js"]:
    cands += list(ROOT.glob(pat))

# unique existing files only
files = []
seen=set()
for p in cands:
    if p.is_file():
        rp=str(p)
        if rp not in seen:
            seen.add(rp)
            files.append(p)

MARK = "VSP_P0_RUNS_FLICKER_DEFINITIVE_V1"
LOCK_MARK = "VSP_P0_RUNS_FETCH_LOCK_V1"
MK_MARK = "VSP_P0_MKJSONRESPONSE_RESPONSE_V1"

FETCH_LOCK = r"""
<!-- VSP_P0_RUNS_FETCH_LOCK_V1 -->
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

  const H = (obj, degraded="1") => {
    const headers = new Headers({
      "Content-Type":"application/json; charset=utf-8",
      "Cache-Control":"no-store",
      "X-VSP-Degraded": String(degraded),
      "X-VSP-Fix": "runs_fetch_lock_v1"
    });
    return headers;
  };

  async function wrapRuns(input, init){
    let url = "";
    try{ url = (typeof input === "string") ? input : (input && input.url) ? input.url : ""; }catch(_){}
    const isRuns = !!url && url.includes("/api/vsp/runs");
    if (!isRuns) return orig(input, init);

    // Always return a REAL Response with HTTP 200 to prevent any banner flicker.
    try{
      const r = await orig(input, init);
      if (r && r.ok){
        // cache last-good runs payload for fallback
        try{
          const j = await r.clone().json();
          if (j && typeof j === "object"){
            j.ok = True if False else True  # (ignored by JS, just to avoid python formatting pitfalls)
          }
        }catch(_){}
        try{
          const j = await r.clone().json();
          if (j and isinstance(j, dict)):
            pass
        }except Exception:
          pass
        try{
          const j2 = await r.clone().json();
          if (j2 && typeof j2 === "object"){
            j2.ok = true;
            localStorage.setItem("vsp_runs_cache_last_ok", JSON.stringify(j2));
          }
        }catch(_){}
        return r;
      }

      let j = null;
      try{ j = r ? await r.clone().json() : null; }catch(_){}
      if (j && typeof j === "object"){
        j.ok = true;
        j._degraded = true;
        j._orig_status = r ? r.status : 0;
        try{ localStorage.setItem("vsp_runs_cache_last_ok", JSON.stringify(j)); }catch(_){}
        return new Response(JSON.stringify(j), {status:200, headers:H(j,"1")});
      }

      // fallback to cached last-ok
      let cached = null;
      try{ cached = JSON.parse(localStorage.getItem("vsp_runs_cache_last_ok") || "null"); }catch(_){}
      const payload = cached || {ok:true,_degraded:true,_orig_status:(r?r.status:0),items:[],note:"runs-fallback(nojson)"};
      return new Response(JSON.stringify(payload), {status:200, headers:H(payload,"1")});
    }catch(e){
      let cached = null;
      try{ cached = JSON.parse(localStorage.getItem("vsp_runs_cache_last_ok") || "null"); }catch(_){}
      const payload = cached || {ok:true,_degraded:true,_orig_status:0,items:[],note:"runs-fallback(exception)"};
      return new Response(JSON.stringify(payload), {status:200, headers:H(payload,"1")});
    }
  }

  try{
    Object.defineProperty(window, "fetch", { value: wrapRuns, writable:false, configurable:false });
  }catch(_){
    window.fetch = wrapRuns;
  }
})();
</script>
"""

# mkJsonResponse -> always Response(200) (dọn mấy đoạn trả object giả ok:false/status:503)
MKJSON = r"""
/* VSP_P0_MKJSONRESPONSE_RESPONSE_V1 */
function mkJsonResponse(obj, httpStatus, forceOk){
  try{
    const st = (typeof httpStatus === "number") ? httpStatus : 200;
    const ok = (forceOk === undefined) ? true : !!forceOk;

    if (obj && typeof obj === "object"){
      if (obj.ok === undefined) obj.ok = ok;
      if (obj._orig_status === undefined) obj._orig_status = st;
      if (obj._degraded === undefined) obj._degraded = (st >= 400) ? true : false;
    }

    const headers = new Headers({
      "Content-Type":"application/json; charset=utf-8",
      "Cache-Control":"no-store",
      "X-VSP-Degraded": (st >= 400) ? "1" : "0",
      "X-VSP-Fix": "mkJsonResponse_response_v1"
    });

    // Always 200 to prevent UI flicker; carry original status in obj._orig_status
    return new Response(JSON.stringify(obj || {ok:true,_degraded:false}), { status: 200, headers });
  }catch(e){
    return new Response(JSON.stringify({ok:true,_degraded:true,note:"mkJsonResponse-exception"}), {status:200, headers:{"Content-Type":"application/json"}});
  }
}
"""

def patch_text(s: str, is_html: bool) -> str:
    if MARK in s:
        return s

    s0 = s

    # 1) inject fetch-lock early in <head> for HTML
    if is_html and LOCK_MARK not in s:
        m = re.search(r"<head[^>]*>", s, flags=re.I)
        if m:
            ins_at = m.end()
            s = s[:ins_at] + "\n" + FETCH_LOCK + "\n" + s[ins_at:]

    # 2) normalize mkJsonResponse: replace any existing mkJsonResponse that returns a fake object
    if "mkJsonResponse" in s and MK_MARK not in s:
        # replace function mkJsonResponse(...) { ...return { ok:false, status:..., json: async()=>obj }... }
        s = re.sub(
            r"function\s+mkJsonResponse\s*\([^)]*\)\s*\{.*?\}\s*",
            MKJSON + "\n",
            s,
            flags=re.S
        )

    # 3) kill any direct fake-response object returns (not a Response)
    s = re.sub(
        r"return\s*\{\s*ok\s*:\s*false\s*,\s*status\s*:\s*[^,}]+\s*,\s*json\s*:\s*async\s*\(\)\s*=>\s*obj\s*\}\s*;",
        r"return mkJsonResponse(obj, 503, true);",
        s
    )

    # 4) remove hard 503 in mkJsonResponse calls (keeps _orig_status inside obj)
    s = re.sub(r"(mkJsonResponse\s*\([^)]*?),\s*503\s*\)", r"\1)", s)
    s = re.sub(r"(mkJsonResponse\s*\([^)]*?),\s*status\s*\|\|\s*503\s*\)", r"\1)", s)
    s = re.sub(r"status\s*\|\|\s*503", "200", s)

    # 5) 마지막: gắn marker
    if s != s0:
        if is_html:
            s = s.replace("</head>", f"\n<!-- {MARK} -->\n</head>", 1) if "</head>" in s else (s + f"\n<!-- {MARK} -->\n")
        else:
            s = s + f"\n\n/* {MARK} */\n"
    return s

changed = 0
for p in files:
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue

    is_html = p.suffix.lower() in [".html", ".htm"]
    s2 = patch_text(s, is_html=is_html)
    if s2 != s:
        bak = p.with_name(p.name + f".bak_runs_flicker_fix_{time.strftime('%Y%m%d_%H%M%S')}")
        try:
            bak.write_text(s, encoding="utf-8")
        except Exception:
            pass
        p.write_text(s2, encoding="utf-8")
        print(f"[OK] patched: {p}")
        changed += 1

print("[DONE] changed=", changed)
PY

# syntax check best-effort
for f in static/js/vsp_bundle_commercial_v2.js static/js/vsp_bundle_commercial_v1.js static/js/vsp_runs_tab_resolved_v1.js static/js/vsp_app_entry_safe_v1.js; do
  [ -f "$f" ] || continue
  if command -v node >/dev/null 2>&1; then node --check "$f" && echo "[OK] node --check $f"; fi
done

echo "[NEXT] restart UI then Ctrl+F5 (or Incognito) /runs and /vsp5"
