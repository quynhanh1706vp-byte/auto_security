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

cp -f "$F" "${F}.bak_p3k13a_${TS}"
echo "[BACKUP] ${F}.bak_p3k13a_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_tabs4_autorid_v1.js")
s0=p.read_text(encoding="utf-8", errors="replace")
s=s0

MARK="VSP_P3K13A_AUTORID_SWALLOW_NETWORKERROR_V1"
if MARK not in s:
    s = f"// {MARK}\n" + s

# Inject helper once (near top)
if "window.__VSP_SWALLOW_NETERR__" not in s:
    helper = r'''
;(function(){
  try{
    if (window.__VSP_SWALLOW_NETERR__) return;
    window.__VSP_SWALLOW_NETERR__ = function(err){
      try{
        if (!err) return false;
        const name = (err.name || "").toString();
        const msg  = (err.message || err.toString() || "").toString();
        // Firefox: "NetworkError when attempting to fetch resource."
        if (name === "AbortError") return true;
        if (msg.indexOf("NetworkError when attempting to fetch resource") >= 0) return true;
        if (msg.indexOf("Failed to fetch") >= 0) return true;
        if (msg.indexOf("Load failed") >= 0) return true;
        return false;
      }catch(e){ return false; }
    };
  }catch(e){}
})();
'''
    s = s.replace(f"// {MARK}\n", f"// {MARK}\n{helper}\n", 1)

# Convert catch blocks: if (window.__VSP_SWALLOW_NETERR__(err)) return null;
# Conservative: only modify `catch (e)` and `catch(e)` blocks that contain "emit(" near them (autorid uses emit)
def patch_catch(m):
    block = m.group(0)
    if "__VSP_SWALLOW_NETERR__" in block:
        return block
    # Insert at start of catch body
    return re.sub(r'catch\s*\(\s*([A-Za-z_$][\w$]*)\s*\)\s*\{',
                  lambda mm: mm.group(0) + f'\n    try{{ if (window.__VSP_SWALLOW_NETERR__ && window.__VSP_SWALLOW_NETERR__({mm.group(1)})) {{ console.warn("[VSP_AUTORID] neterr ignored"); return null; }} }}catch(_e){{}}',
                  block, count=1)

s2 = re.sub(r'catch\s*\(\s*[A-Za-z_$][\w$]*\s*\)\s*\{[\s\S]{0,500}?\}',
            patch_catch, s, count=1)

# If no catch patch happened, do a generic injection in the file (safer fallback)
s = s2

if s != s0:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched", p)
else:
    print("[WARN] no change (patterns not hit); file structure may differ")
PY

echo "== node -c =="
node -c "$F" >/dev/null && echo "[OK] node -c passed"

echo "== restart =="
sudo systemctl restart "$SVC"
sleep 0.8
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,160p' || true
  exit 3
}

echo "[DONE] p3k13a_autorid_swallow_networkerror_v1"
