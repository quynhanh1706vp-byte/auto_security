#!/usr/bin/env bash
set -euo pipefail
TS="$(date +%Y%m%d_%H%M%S)"

for f in \
  static/js/vsp_runs_trigger_scan_ui_v3.js \
  static/js/vsp_runs_trigger_scan_mount_hook_v1.js
do
  [ -f "$f" ] || continue
  cp "$f" "$f.bak_disable_${TS}"
  python3 - << PY
from pathlib import Path
p = Path("$f")
txt = p.read_text(encoding="utf-8", errors="replace")
if "VSP_DISABLE_LEGACY_RUNSCAN_V1" not in txt:
    txt = "(function(){/*VSP_DISABLE_LEGACY_RUNSCAN_V1*/return;})();\n" + txt
    p.write_text(txt, encoding="utf-8")
    print("[OK] disabled", p.name)
else:
    print("[SKIP] already disabled", p.name)
PY
done

echo "[DONE] legacy runscan disabled"
