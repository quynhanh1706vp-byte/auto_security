#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p464e2_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P464E2_PING_ON_EXPORTS_RENDER_V1"
if MARK in s:
    print("[OK] already patched ping-on-render")
    raise SystemExit(0)

# Insert a small ping inside the exports render function if present (P464b)
# We'll locate "function vspRender(root){" and inject after it creates the box
pat = re.compile(r"(function\s+vspRender\s*\(\s*root\s*\)\s*\{\s*)", re.M)
m = pat.search(s)
if not m:
    # fallback: append ping helper at end
    inject = "\n/* "+MARK+" */\nfetch('/api/vsp/p464_ping',{credentials:'same-origin'}).catch(()=>{});\n"
    p.write_text(s + inject, encoding="utf-8")
    print("[WARN] vspRender not found; appended fallback ping")
    raise SystemExit(0)

insert_pos = m.end(1)
ping = """
  // --- VSP_P464E2_PING_ON_EXPORTS_RENDER_V1 ---
  try{ fetch('/api/vsp/p464_ping', {credentials:'same-origin'}).catch(function(){}); }catch(e){}
  // --- /VSP_P464E2_PING_ON_EXPORTS_RENDER_V1 ---
"""
s2 = s[:insert_pos] + ping + s[insert_pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected ping inside vspRender")
PY

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart vsp-ui-8910.service || true
  sudo systemctl is-active vsp-ui-8910.service || true
fi

echo "[OK] DONE. Now open /runs in browser once, then check api_hit log for /api/vsp/p464_ping"
