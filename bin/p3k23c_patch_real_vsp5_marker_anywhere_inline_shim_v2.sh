#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
KEY="VSP_P1_FINAL_MARKERS_FORCE_V4:vsp5"
MARK="VSP_P3K23C_INLINE_EARLY_SHIM_REAL_VSP5_ANYWHERE_V2"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need curl
command -v systemctl >/dev/null 2>&1 || true

tmp="$(mktemp -d /tmp/vsp_p3k23c_v2_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "== [0] locate REAL running file(s) (exclude bin/, releases/, out*, .venv, broken/backups) =="
grep -RIl \
  --exclude='*.bak_*' --exclude='*.disabled_*' --exclude='*.broken_*' \
  --exclude-dir='bin' --exclude-dir='releases' --exclude-dir='out' --exclude-dir='out_ci' --exclude-dir='.venv' \
  "$KEY" . 2>/dev/null | sort -u > "$tmp/all.txt" || true

# Prefer: root wsgi_vsp_ui_gateway.py, then templates/*.html, else any remaining
{
  grep -E '(^|/)(wsgi_vsp_ui_gateway\.py)$' "$tmp/all.txt" || true
  grep -E '(^|/)templates/.*\.(html|htm|jinja|j2)$' "$tmp/all.txt" || true
  grep -v -E '(^|/)templates/.*\.(html|htm|jinja|j2)$|(^|/)(wsgi_vsp_ui_gateway\.py)$' "$tmp/all.txt" || true
} > "$tmp/targets.txt"

if [ ! -s "$tmp/targets.txt" ]; then
  echo "[WARN] KEY not found (maybe built differently). Fallback: patch templates containing vsp_bundle_tabs5_v1.js"
  grep -RIl \
    --exclude='*.bak_*' --exclude='*.disabled_*' \
    --exclude-dir='bin' --exclude-dir='releases' --exclude-dir='out' --exclude-dir='out_ci' --exclude-dir='.venv' \
    'vsp_bundle_tabs5_v1\.js' templates 2>/dev/null | sort -u > "$tmp/targets.txt" || true
fi

if [ ! -s "$tmp/targets.txt" ]; then
  echo "[ERR] cannot find patch targets."
  echo "Run: grep -RIn '$KEY' . | head"
  exit 2
fi

echo "[OK] patch targets:"
sed -n '1,120p' "$tmp/targets.txt"

echo "== [1] patch (NO f-string; safe template replace) =="
python3 - "$tmp/targets.txt" "$TS" "$MARK" "$KEY" <<'PY'
from pathlib import Path
import re, sys

targets_txt = Path(sys.argv[1])
ts = sys.argv[2]
mark = sys.argv[3]
key = sys.argv[4]

INLINE_TPL = r"""<!-- === __MARK__ === -->
<script>
(function(){
  try{
    if (window.__VSP_EARLY_SAFE_SHIM__) return;
    window.__VSP_EARLY_SAFE_SHIM__ = true;

    function _s(x){ try{ return String((x && (x.message||x)) || x || ""); }catch(e){ return ""; } }
    function _isNoise(x){ const s=_s(x); return /timeout|AbortError|NS_BINDING_ABORTED|NetworkError/i.test(s); }

    // swallow noisy promise rejections early (Firefox)
    window.addEventListener('unhandledrejection', function(ev){
      try{ if (_isNoise(ev && ev.reason)) { ev.preventDefault(); return; } }catch(e){}
    });

    window.addEventListener('error', function(ev){
      try{
        const msg = ev && (ev.message || (ev.error && ev.error.message) || ev.error);
        if (_isNoise(msg)) { ev.preventDefault(); return true; }
      }catch(e){}
    }, true);

    const sp = new URLSearchParams(location.search || "");
    const urlRid = sp.get("rid") || "";

    // If ?rid= exists => never call rid_latest* (return url rid immediately)
    if (urlRid && window.fetch && !window.__VSP_EARLY_FETCH_SHIM__){
      const _fetch = window.fetch.bind(window);
      window.fetch = function(input, init){
        try{
          const u = (typeof input === "string") ? input : (input && input.url) || "";
          if (/\/api\/vsp\/rid_latest(_v3)?\b/.test(u)) {
            const body = JSON.stringify({ok:true, rid:urlRid, mode:"url"});
            return Promise.resolve(new Response(body, {status:200, headers: {"Content-Type":"application/json"}}));
          }
        }catch(e){}
        return _fetch(input, init).catch(function(e){
          if (_isNoise(e)) return new Response("{}", {status:200, headers: {"Content-Type":"application/json"}});
          throw e;
        });
      };
      window.__VSP_EARLY_FETCH_SHIM__ = true;
    }
  }catch(e){}
})();
</script>
"""

INLINE = INLINE_TPL.replace("__MARK__", mark)

files = [line.strip() for line in targets_txt.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()]
patched = 0

for fp in files:
  p = Path(fp)
  if not p.exists():
    continue
  s = p.read_text(encoding="utf-8", errors="replace")
  if mark in s:
    print("[SKIP] already:", fp)
    continue

  bak = p.with_name(p.name + f".bak_p3k23c_v2_{ts}")
  bak.write_text(s, encoding="utf-8")

  out = s
  suf = p.suffix.lower()

  is_html = suf in [".html", ".htm", ".jinja", ".j2"]
  if is_html:
    m = re.search(r'(?is)<head[^>]*>', out)
    if m:
      out = out[:m.end()] + "\n" + INLINE + "\n" + out[m.end():]
    else:
      k = out.find(key)
      if k != -1:
        out = out[:k+len(key)] + "\n" + INLINE + "\n" + out[k+len(key):]
      else:
        out = INLINE + "\n" + out
  else:
    # non-HTML file: inject right after KEY if present, else prepend
    k = out.find(key)
    if k != -1:
      out = out[:k+len(key)] + "\n" + INLINE + "\n" + out[k+len(key):]
    else:
      out = INLINE + "\n" + out

  p.write_text(out, encoding="utf-8")
  print("[PATCH]", fp, "backup=", bak.name)
  patched += 1

print("[DONE] patched=", patched)
PY

echo "== [2] restart =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"

echo "== [3] smoke: marker must appear in served /vsp5 HTML =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print((json.load(sys.stdin) or {}).get("rid",""))' 2>/dev/null || true)"
[ -n "${RID:-}" ] || RID="VSP_CI_20251219_092640"

curl -fsS "$BASE/vsp5?rid=$RID" | grep -n "$MARK" | head -n 3 && echo "[OK] marker present in /vsp5 HTML" || {
  echo "[FAIL] marker missing in /vsp5 HTML"
  echo "Next: patch the real route renderer in vsp_demo_app.py"
  exit 2
}

echo "[DONE] p3k23c_patch_real_vsp5_marker_anywhere_inline_shim_v2"
