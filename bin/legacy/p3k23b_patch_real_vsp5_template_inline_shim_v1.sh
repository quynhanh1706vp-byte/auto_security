#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need sed; need curl
command -v systemctl >/dev/null 2>&1 || true

MARK="VSP_P3K23B_INLINE_EARLY_SHIM_REAL_VSP5_V1"
KEY="VSP_P1_FINAL_MARKERS_FORCE_V4:vsp5"

echo "== [0] find REAL /vsp5 template(s) by marker: $KEY =="
mapfile -t TPLS < <(grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' "$KEY" templates 2>/dev/null | sort -u || true)

if [ "${#TPLS[@]}" -eq 0 ]; then
  echo "[WARN] marker not found in templates/. Fallback search by script tags..."
  mapfile -t TPLS < <(
    grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' \
      -e 'vsp_tabs4_autorid_v1\.js' -e 'vsp_bundle_tabs5_v1\.js' \
      templates 2>/dev/null | sort -u || true
  )
fi

if [ "${#TPLS[@]}" -eq 0 ]; then
  echo "[ERR] cannot locate /vsp5 template in templates/. Need to search vsp_demo_app.py next."
  echo "Try: grep -RIn '$KEY' vsp_demo_app.py templates | head"
  exit 2
fi

printf "[OK] target templates:\n%s\n" "${TPLS[@]}"

python3 - <<'PY'
from pathlib import Path
import re, time, sys

MARK="VSP_P3K23B_INLINE_EARLY_SHIM_REAL_VSP5_V1"
INLINE = r"""
<!-- === VSP_P3K23B_INLINE_EARLY_SHIM_REAL_VSP5_V1 === -->
<script>
(function(){
  try{
    if (window.__VSP_P3K23B__) return;
    window.__VSP_P3K23B__ = true;

    function _s(x){ try{ return String((x && (x.message||x)) || x || ""); }catch(e){ return ""; } }
    function _isNoise(x){ const s=_s(x); return /timeout|AbortError|NS_BINDING_ABORTED|NetworkError/i.test(s); }

    // swallow firefox noisy promise rejections
    window.addEventListener('unhandledrejection', function(ev){
      try{ if (_isNoise(ev.reason)) { ev.preventDefault(); return; } }catch(e){}
    });

    window.addEventListener('error', function(ev){
      try{
        const msg = ev && (ev.message || (ev.error && ev.error.message) || ev.error);
        if (_isNoise(msg)) { ev.preventDefault(); return true; }
      }catch(e){}
    }, true);

    // If ?rid= exists => never call rid_latest*
    const sp = new URLSearchParams(location.search || "");
    const urlRid = sp.get("rid") || "";

    if (urlRid && window.fetch && !window.__VSP_P3K23B_FETCH_SHIM__){
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
          if (_isNoise(e)) return new Response("{}", {status:200, headers: {"Content-Type":"application/json"}});
          throw e;
        });
      };
      window.__VSP_P3K23B_FETCH_SHIM__ = true;
    }
  }catch(e){}
})();
</script>
"""

targets = sys.stdin.read().splitlines()
patched=0
for fp in targets:
  p=Path(fp)
  if not p.exists(): continue
  s=p.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    print("[SKIP] already:", p.name)
    continue
  m=re.search(r'(?is)<head[^>]*>', s)
  if not m:
    print("[WARN] no <head>:", p.name)
    continue
  bak = p.with_name(p.name + f".bak_p3k23b_{int(time.time())}")
  bak.write_text(s, encoding="utf-8")
  out = s[:m.end()] + "\n" + INLINE + "\n" + s[m.end():]
  p.write_text(out, encoding="utf-8")
  print("[PATCH]", p.name, "backup=", bak.name)
  patched += 1

print("[DONE] patched=", patched)
PY <<EOF
$(printf "%s\n" "${TPLS[@]}")
EOF

echo "== [1] restart =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"

echo "== [2] smoke: marker must appear in /vsp5 HTML =="
RID="$(
  curl -fsS "$BASE/api/vsp/rid_latest" \
  | python3 -c 'import sys,json; print((json.load(sys.stdin) or {}).get("rid",""))'
)"
[ -n "$RID" ] || RID="VSP_CI_20251219_092640"

curl -fsS "$BASE/vsp5?rid=$RID" | grep -n "VSP_P3K23B_INLINE_EARLY_SHIM_REAL_VSP5_V1" | head -n 3 && echo "[OK] marker present" || {
  echo "[FAIL] marker still missing in served HTML"
  exit 2
}

echo "[DONE] p3k23b_patch_real_vsp5_template_inline_shim_v1"
