#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_usev2_${TS}"
echo "[BACKUP] ${JS}.bak_usev2_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_MINICHARTS_USE_TOPFIND_V2_V1"
if marker in s:
    print("[OK] already patched", marker)
else:
    # Replace any occurrences of top_findings_v1 or v2 old variants to the canonical v2
    s2=s
    s2=s2.replace("/api/vsp/top_findings_v1", "/api/vsp/top_findings_v2")
    # if some code uses full URL pieces or template strings, also patch common token
    s2=s2.replace("top_findings_v1", "top_findings_v2")
    if s2==s:
        # still append a very small shim for safety (runtime override)
        shim = r'''
/* ===== VSP_P1_MINICHARTS_USE_TOPFIND_V2_V1 ===== */
try{
  window.__VSP_TOPFIND_ENDPOINT = "/api/vsp/top_findings_v2";
}catch(e){}
'''
        s2 = s2.rstrip() + "\n\n" + shim + "\n"
    else:
        s2 = s2 + "\n/* ===== VSP_P1_MINICHARTS_USE_TOPFIND_V2_V1 ===== */\n"
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched:", marker)

PY

node --check "$JS" >/dev/null
echo "[OK] node --check PASS: $JS"
echo "[DONE] Ctrl+Shift+R rồi mở: http://127.0.0.1:8910/vsp5?rid=VSP_CI_20251218_114312"
