#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_silence_degradedlog_${TS}"
echo "[BACKUP] ${JS}.bak_silence_degradedlog_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_SILENCE_DEGRADED_LOG_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

# Comment out the specific log line(s)
pat = re.compile(r'^\s*console\.(log|info|warn)\(\s*\[\s*["\']\[VSP\]\[P2\]\s*Degraded banner shown:.*?\)\s*;\s*$', re.M)
s2 = pat.sub(lambda m: "/* "+MARK+" */\n// "+m.group(0).lstrip(), s)

# Fallback: if pattern not found, do a safer replace on the token
if s2 == s:
    s2 = s.replace("[VSP][P2] Degraded banner shown", "[VSP][P2] Degraded banner shown (silenced)")
    s2 = "/* "+MARK+" */\n" + s2

p.write_text(s2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check: syntax OK"
grep -n "VSP_P0_SILENCE_DEGRADED_LOG_V1" "$JS" | head -n 2 && echo "[OK] marker present"
