#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_ui_loader_route_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

# restore latest backup (the one we just made)
B="$(ls -1t ${F}.bak_ddloader_* 2>/dev/null | head -n1 || true)"
[ -n "${B:-}" ] || { echo "[ERR] cannot find backup ${F}.bak_ddloader_*"; exit 3; }
cp -f "$B" "$F"
echo "[RESTORE] $F <= $B"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_ui_loader_route_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

impl = "/static/js/vsp_drilldown_artifacts_impl_commercial_v1.js"

if impl in s:
    print("[OK] loader already references impl; skip")
    raise SystemExit(0)

# Method 1: insert a push line right before dashboard_enhance push
pat = r"(?m)^([ \t]*)scripts\.push\(\s*['\"](/static/js/vsp_dashboard_enhance_v1\.js)['\"]\s*\)\s*;.*$"
m = re.search(pat, s)
if m:
    indent = m.group(1)
    insert = indent + f"scripts.push('{impl}');\n"
    s = s[:m.start()] + insert + s[m.start():]
    p.write_text(s, encoding="utf-8")
    print("[OK] inserted impl push before dashboard_enhance push")
    raise SystemExit(0)

# Method 2: if dashboard scripts are an array literal, inject impl just before enhance string
if "/static/js/vsp_dashboard_enhance_v1.js" in s:
    s2 = s.replace("/static/js/vsp_dashboard_enhance_v1.js",
                   impl + "', '/static/js/vsp_dashboard_enhance_v1.js", 1)
    # normalize quotes for the injected part (ensure it becomes 'impl', 'enhance')
    s2 = s2.replace(impl + "', '/static/js/vsp_dashboard_enhance_v1.js",
                    impl + "', '/static/js/vsp_dashboard_enhance_v1.js")
    # also ensure we didn't create ''/static
    s2 = s2.replace("''/static/js", "'/static/js")
    p.write_text(s2, encoding="utf-8")
    print("[OK] injected impl near dashboard_enhance string (fallback)")
    raise SystemExit(0)

raise SystemExit("[ERR] cannot locate dashboard_enhance entry to insert before")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK: $F"
echo "[OK] fixed loader"
