#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_guard_${TS}"
echo "[BACKUP] ${JS}.bak_guard_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_gate_story_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
mark="VSP_P0_GATE_STORY_GUARD_ONCE_V2"
if mark in s:
    print("[SKIP] already guarded")
    raise SystemExit(0)

guard = """/* VSP_P0_GATE_STORY_GUARD_ONCE_V2 */
(()=>{ try{ if(window.__vsp_gate_story_once_v2) return; window.__vsp_gate_story_once_v2=true; }catch(e){} })();
"""
p.write_text(guard + "\n" + s, encoding="utf-8")
print("[OK] inserted guard once")
PY

echo "[DONE] reload /vsp5"
