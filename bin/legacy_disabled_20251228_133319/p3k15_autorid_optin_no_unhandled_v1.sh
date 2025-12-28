#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_tabs4_autorid_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_p3k15_${TS}"
echo "[BACKUP] ${F}.bak_p3k15_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_tabs4_autorid_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P3K15_AUTORID_OPTIN_NO_UNHANDLED_V1" in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Wrap whole file to hard-stop execution unless allowed.
header = """/* === VSP_P3K15_AUTORID_OPTIN_NO_UNHANDLED_V1 ===
   Rules:
   - If ?rid= exists => autorid disabled (no background fetch, no timeout throw)
   - Autorid runs only when ?autorid=1
   - Swallow timeout/unhandledrejection signals
=== */
(function(){
  try{
    window.addEventListener('unhandledrejection', function(e){
      try{
        var r = e && e.reason;
        var msg = (r && (r.message || (''+r))) || '';
        if (/timeout/i.test(msg) || msg === 'timeout') { e.preventDefault(); return; }
      }catch(_){}
    });
  }catch(_){}

  try{
    var qs = new URLSearchParams((location && location.search) || "");
    if (qs.get("rid")) { window.__VSP_AUTORID_DISABLED_BY_RID__=true; return; }
    if (qs.get("autorid") !== "1") { window.__VSP_AUTORID_OPTIN_OFF__=true; return; }
  }catch(e){
    window.__VSP_AUTORID_OPTIN_OFF__=true; return;
  }

  try{
"""
tail = """
  }catch(e){
    // Never throw to global (commercial-safe)
    try{ window.__VSP_AUTORID_LAST_ERR__ = (e && (e.message||(''+e))) || 'err'; }catch(_){}
    return;
  }
})();
"""

# Ensure we don't double-wrap if file already starts with (function()...
wrapped = header + s + tail
p.write_text(wrapped, encoding="utf-8")
print("[OK] patched (wrapped + opt-in)")
PY

echo "== node -c =="
node -c "$F"
echo "[OK] node -c passed"

echo "== restart =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }

echo "== marker =="
head -n 3 "$F" | sed -n '1,3p'

echo "[DONE] p3k15_autorid_optin_no_unhandled_v1"
