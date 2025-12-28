#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_tabs_hash_router_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

grep -q "rules: *'panel-rules'" "$F" && { echo "[OK] rules pane id already panel-rules"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rules_paneid_${TS}"
echo "[BACKUP] $F.bak_rules_paneid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_tabs_hash_router_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the mapping only (safe)
s2=re.sub(r"(rules\s*:\s*')([^']+)(')", lambda m: m.group(1)+("panel-rules" if m.group(2)=="vsp-rules-main" else m.group(2))+m.group(3), s, count=1)

# If still unchanged but 'vsp-rules-main' exists anywhere, replace that string as fallback
if s2==s and "vsp-rules-main" in s:
    s2=s.replace("vsp-rules-main", "panel-rules")

p.write_text(s2, encoding="utf-8")
print("[OK] patched rules pane id => panel-rules")
PY

grep -n "rules:" -n "$F" | head -n 5
grep -n "ROUTE_RULES_V1" -n "$F" | head -n 5
