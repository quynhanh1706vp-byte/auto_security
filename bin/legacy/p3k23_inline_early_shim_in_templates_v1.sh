#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

MARK="VSP_P3K23_INLINE_EARLY_SHIM_V1"
TEMPL_DIR="templates"
[ -d "$TEMPL_DIR" ] || { echo "[ERR] missing templates/"; exit 2; }

echo "== [0] find candidate templates =="
mapfile -t CANDS < <(
  grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' \
    -e 'vsp_bundle_tabs5_v1\.js' -e 'vsp_tabs4_autorid_v1\.js' \
    "$TEMPL_DIR" | sort -u
)
if [ "${#CANDS[@]}" -eq 0 ]; then
  echo "[ERR] cannot find any template containing tabs5/autorid scripts"
  exit 2
fi
printf "[OK] candidates:\n%s\n" "${CANDS[@]}"

python3 - <<'PY'
from pathlib import Path
import re, time

MARK="VSP_P3K23_INLINE_EARLY_SHIM_V1"

INLINE = r"""
<!-- === VSP_P3K23_INLINE_EARLY_SHIM_V1 === -->
<script>
(function(){
  try{
    if (window.__VSP_P3K23__) return;
    window.__VSP_P3K23__ = true;

    function _s(x){
      try { return String((x && (x.message||x)) || x || ""); } catch(e){ return ""; }
    }
    function _isNoise(x){
      const s = _s(x);
      return /timeout|AbortError|NS_BINDING_ABORTED|NetworkError/i.test(s);
    }

    // Swallow Firefox noisy promise rejections (commercial-safe)
    window.addEventListener('unhandledrejection', function(ev){
      try{
        if (_isNoise(ev.reason)) { ev.preventDefault(); return; }
      }catch(e){}
    });

    // Swallow noisy errors
    window.addEventListener('error', function(ev){
      try{
        const msg = ev && (ev.message || (ev.error && ev.error.message) || ev.error);
        if (_isNoise(msg)) { ev.preventDefault(); return true; }
      }catch(e){}
    }, true);

    // If ?rid= exists => never call rid_latest*, return url rid immediately.
    const sp = new URLSearchParams(location.search || "");
    const urlRid = sp.get("rid") || "";

    if (urlRid && window.fetch && !window.__VSP_P3K23_FETCH_SHIM__){
      const _fetch = window.fetch.bind(window);
      window.fetch = function(input, init){
        try{
          const u = (typeof input === "string") ? input : (input && input.url) || "";
          if (/\/api\/vsp\/rid_latest(_v3)?\b/.test(u)){
            const body = JSON.stringify({ok:true, rid:urlRid, mode:"url"});
            return Promise.resolve(new Response(body, {status:200, headers: {"Content-Type":"application/json"}}));
          }
        }catch(e){}
        return _fetch(input, init).catch(function(e){
          if (_isNoise(e)) {
            // fail-soft: return empty json, no throw
            return new Response("{}", {status:200, headers: {"Content-Type":"application/json"}});
          }
          throw e;
        });
      };
      window.__VSP_P3K23_FETCH_SHIM__ = true;
    }
  }catch(e){}
})();
</script>
"""

tpl_dir = Path("templates")
files = [Path(p) for p in __import__("glob").glob(str(tpl_dir/"*.html"))]

# Only patch templates that include tabs5 or autorid script tags
targets=[]
for f in files:
  try:
    s=f.read_text(encoding="utf-8", errors="replace")
  except Exception:
    continue
  if ("vsp_bundle_tabs5_v1.js" in s) or ("vsp_tabs4_autorid_v1.js" in s):
    targets.append(f)

if not targets:
  raise SystemExit("No target templates found")

for f in targets:
  s=f.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    print("[SKIP] already:", f.name)
    continue

  # insert right after <head ...>
  m=re.search(r'(?is)<head[^>]*>', s)
  if not m:
    print("[WARN] no <head>:", f.name)
    continue

  ins_at=m.end()
  out = s[:ins_at] + "\n" + INLINE + "\n" + s[ins_at:]
  bak = f.with_name(f.name + f".bak_p3k23_{int(time.time())}")
  bak.write_text(s, encoding="utf-8")
  f.write_text(out, encoding="utf-8")
  print("[PATCH]", f.name, "backup=", bak.name)

print("[DONE] patched templates=", len(targets))
PY

echo "== [1] restart =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"

echo "== [2] smoke: ensure inline shim present in /vsp5 HTML =="
RID="$(
  curl -fsS "$BASE/api/vsp/rid_latest" \
  | python3 -c 'import sys,json; print((json.load(sys.stdin) or {}).get("rid",""))'
)"
[ -n "$RID" ] || RID="VSP_CI_20251219_092640"
curl -fsS "$BASE/vsp5?rid=$RID" | grep -n "VSP_P3K23_INLINE_EARLY_SHIM_V1" -n | head -n 3 || {
  echo "[FAIL] shim marker not found in served HTML. /vsp5 may use a different template."
  exit 2
}
echo "[OK] shim marker found"
echo "[DONE] p3k23_inline_early_shim_in_templates_v1"
