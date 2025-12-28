#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sudo

files=(
  "static/js/vsp_runs_quick_actions_v1.js"
  "static/js/vsp_runs_kpi_compact_v3.js"
)

python3 - <<'PY'
from pathlib import Path
import datetime

ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
marker="VSP_P432_BOOT_SHIM_V1"
shim=";(()=>{ /* VSP_P432_BOOT_SHIM_V1 */ window.boot = window.boot || {}; })();\n"

files=[
  Path("static/js/vsp_runs_quick_actions_v1.js"),
  Path("static/js/vsp_runs_kpi_compact_v3.js"),
]
patched=0
for p in files:
  if not p.exists(): 
    print("[WARN] missing", p); 
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  if marker in s:
    print("[OK] already patched", p); 
    continue
  bak=p.with_suffix(p.suffix+f".bak_p432_{ts}")
  bak.write_text(s, encoding="utf-8")
  p.write_text(shim+s, encoding="utf-8")
  patched += 1
  print("[OK] patched", p, "backup=", bak.name)
print("patched=", patched)
PY

sudo systemctl restart vsp-ui-8910.service
echo "[OK] restarted"
