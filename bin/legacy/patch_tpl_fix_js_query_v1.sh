#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_fix_jsquery_${TS}"
echo "[BACKUP] $T.bak_fix_jsquery_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("templates/vsp_4tabs_commercial_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")

# src="/static/js/xxx.js"?v=123  -> src="/static/js/xxx.js?v=123"
new = re.sub(r'(src="[^"]+?\.js)"\?v=([0-9_]+)"', r'\1?v=\2"', s)
# also handle: src='...js'?v=...'
new = re.sub(r"(src='[^']+?\.js)'\?v=([0-9_]+)'", r"\1?v=\2'", new)

if new == s:
    print("[WARN] no broken js ?v pattern found (skip)")
else:
    p.write_text(new, encoding="utf-8")
    print("[OK] fixed broken script query patterns")
PY

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_wait_v1.sh
