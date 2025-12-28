#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_cool_${TS}"
echo "[BACKUP] ${F}.bak_cool_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_gate_story_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_GATE_STORY_COOLDOWN_V1"
if marker in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Insert a global cooldown guard near top (after proxies)
ins = r"""
/* VSP_P1_GATE_STORY_COOLDOWN_V1 */
window.__vsp_gate_story_last_ok_ts = window.__vsp_gate_story_last_ok_ts || 0;
window.__vsp_gate_story_cooldown_ms = window.__vsp_gate_story_cooldown_ms || 15000;
"""
# put after the proxy install logs (or at file start)
s = ins + "\n" + s

# Patch common pattern: if (ok) { ... } else { retry... }
# We'll add: when response is 200 + JSON => set last_ok_ts, and skip immediate retry loops.
s2, n = re.subn(
    r'(\bstatus\s*===\s*200\b[\s\S]{0,200}?\{)',
    r'window.__vsp_gate_story_last_ok_ts=Date.now();\n\1',
    s,
    count=1
)

# Also, before any fetch loop begins, add a check:
# if (Date.now()-last_ok_ts < cooldown) return;
s3, n2 = re.subn(
    r'(\bfunction\s+[A-Za-z0-9_$]+\s*\([^)]*\)\s*\{\s*)',
    r'\1try{ if(Date.now()-window.__vsp_gate_story_last_ok_ts < window.__vsp_gate_story_cooldown_ms){ return; } }catch(e){}\n',
    s2,
    count=1
)

p.write_text(s3, encoding="utf-8")
print("[OK] patched cooldown:", marker, "n=", n, "n2=", n2)
PY

echo "[OK] done. Ctrl+F5 /vsp5"
