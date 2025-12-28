#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v node >/dev/null 2>&1 || { echo "[WARN] node not found -> skip node --check"; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) Patch templates: inject preload fetch shim BEFORE any dashboard JS
python3 - <<'PY'
from pathlib import Path
import re, time

TPL_DIR = Path("templates")
if not TPL_DIR.exists():
    print("[WARN] templates/ not found -> skip template inject")
    raise SystemExit(0)

MARK = "VSP_P2_6C_DASH_FETCH_SHIM_PRELOAD_V1"
SHIM = r"""
<!-- ===================== VSP_P2_6C_DASH_FETCH_SHIM_PRELOAD_V1 ===================== -->
<script>
(function(){
  if(window.__VSP_FETCH_SHIM_PRELOAD_V1) return;
  window.__VSP_FETCH_SHIM_PRELOAD_V1 = true;

  // Root fallback helper (used by some dash scripts)
  window.__VSP_DASH_ROOT = function(){
    return document.querySelector('#vsp-dashboard-main')
        || document.querySelector('#vsp_dashboard_main')
        || document.querySelector('#vsp-dashboard')
        || document.body;
  };

  const _fetch = window.fetch ? window.fetch.bind(window) : null;
  if(!_fetch) return;

  window.fetch = async function(input, init){
    try{
      if(init && typeof init === 'object'){
        const m = String(init.method || '').toUpperCase();
        if(m === 'HEAD'){
          init = Object.assign({}, init, {method:'GET'});
        }
      }
    }catch(e){}

    const res = await _fetch(input, init);

    try{
      const url = (typeof input === 'string') ? input : (input && input.url) || '';
      // unwrap wrapper payload for findings_unified.json
      if(url.includes('/api/vsp/run_file_allow') && url.includes('path=findings_unified.json')){
        const clone = res.clone();
        const j = await clone.json().catch(()=>null);
        if(j && j.ok === true && Array.isArray(j.findings)){
          const body = JSON.stringify({ meta: j.meta || {}, findings: j.findings || [] });
          return new Response(body, { status: res.status, headers: res.headers });
        }
      }
    }catch(e){}

    return res;
  };
})();
</script>
<!-- ===================== /VSP_P2_6C_DASH_FETCH_SHIM_PRELOAD_V1 ===================== -->
""".strip()

patched = 0
for p in TPL_DIR.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="ignore")
    # only inject into templates that look like dashboard/vsp5 pages
    if ("vsp_dashboard" not in s and "/vsp5" not in s and "VSP • Dashboard" not in s and "VSP Dashboard" not in s):
        continue
    if MARK in s:
        continue

    # inject right after <head> (best), else before first <script src="/static/js/vsp_dashboard
    if "<head" in s:
        s2 = re.sub(r"(<head[^>]*>)", r"\1\n" + SHIM + "\n", s, count=1, flags=re.IGNORECASE)
    else:
        s2 = s

    if s2 == s:
        # fallback insert before first dashboard js include
        s2 = re.sub(r"(<script[^>]+src=['\"]/static/js/vsp_dashboard[^>]+>)", SHIM + "\n\\1", s, count=1, flags=re.IGNORECASE)

    if s2 != s:
        bak = p.with_suffix(p.suffix + f".bak_p2_6c_{time.strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(s, encoding="utf-8")
        p.write_text(s2, encoding="utf-8")
        patched += 1
        print(f"[OK] injected shim into {p} (bak {bak.name})")

print(f"[DONE] template_injected={patched}")
PY

# 2) Patch dashboard JS: root fallback + HEAD->GET (best-effort)
python3 - <<'PY'
from pathlib import Path
import re, time

JS_DIR = Path("static/js")
if not JS_DIR.exists():
    raise SystemExit("[ERR] static/js not found")

MARK = "VSP_P2_6C_DASH_ROOT_FALLBACK_V1"

def patch_text(s: str) -> str:
    out = s

    # HEAD -> GET
    out = re.sub(r'(method\s*:\s*)(["\'])HEAD\2', r'\1"GET"', out)
    out = re.sub(r'(method\s*=\s*)(["\'])HEAD\2', r'\1"GET"', out)

    # root fallback (common patterns)
    out = out.replace("document.querySelector('#vsp-dashboard-main')",
                      "(document.querySelector('#vsp-dashboard-main') || (window.__VSP_DASH_ROOT?window.__VSP_DASH_ROOT():document.body))")
    out = out.replace('document.querySelector("#vsp-dashboard-main")',
                      '(document.querySelector("#vsp-dashboard-main") || (window.__VSP_DASH_ROOT?window.__VSP_DASH_ROOT():document.body))')

    # also handle const/let/var root assignments
    out = re.sub(r'(\b(?:const|let|var)\s+root\s*=\s*)document\.querySelector\((["\'])#vsp-dashboard-main\2\)',
                 r'\1(window.__VSP_DASH_ROOT?window.__VSP_DASH_ROOT():document.body)', out)

    # add a marker comment once
    if MARK not in out and out != s:
        out = "/* " + MARK + " */\n" + out
    return out

patched = 0
cands = list(JS_DIR.glob("vsp_dashboard*.js"))
for p in cands:
    s = p.read_text(encoding="utf-8", errors="ignore")
    s2 = patch_text(s)
    if s2 != s:
        bak = p.with_suffix(p.suffix + f".bak_p2_6c_{time.strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(s, encoding="utf-8")
        p.write_text(s2, encoding="utf-8")
        patched += 1
        print(f"[OK] patched {p} (bak {bak.name})")

print(f"[DONE] js_patched={patched} candidates={len(cands)}")
PY

# 3) node check the likely dashboard files
if command -v node >/dev/null 2>&1; then
  for f in static/js/vsp_dashboard*.js; do
    [ -f "$f" ] || continue
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 2; }
  done
fi

echo
echo "[NEXT] Ctrl+Shift+R /vsp5"
echo "Expect:"
echo "  - no more 'Fetch failed loading: HEAD ... vsp_dashboard_luxe...'"
echo "  - no more '[VSP_DASH_FORCE] ... không thấy #vsp-dashboard-main'"
echo "  - no more 'Findings payload mismatch ...'"
