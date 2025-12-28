#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_run_files_compat_${TS}"
echo "[BACKUP] ${APP}.bak_run_files_compat_${TS}"

python3 - "$APP" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P0_API_RUN_FILES_V1_WHITELIST" not in s:
    print("[ERR] run_files_v1 block marker not found (did you insert it into this file?)")
    raise SystemExit(2)

changed = 0

# 1) Flask compat: replace @app.get with @app.route(..., methods=["GET"])
s2, n = re.subn(
    r'@app\.get\(\s*["\']\/api\/vsp\/run_files_v1["\']\s*\)',
    '@app.route("/api/vsp/run_files_v1", methods=["GET"])',
    s,
    count=1
)
if n:
    s = s2
    changed += 1

# 2) Ensure import re exists inside function (safe even if global)
# Insert "import re" into the function import block if missing
func_pat = r'(def api_vsp_run_files_v1\(\):[\s\S]*?^\s*import os, time\s*$)'
m = re.search(func_pat, s, flags=re.M)
if m:
    block = m.group(0)
    # if "import re" already in nearby area, skip
    nearby = s[m.start(): m.start()+600]
    if "import re" not in nearby:
        s = s[:m.end()] + "\n    import re" + s[m.end():]
        changed += 1
else:
    # If we can't find the import line, still try a simpler injection after function def
    m2 = re.search(r'(def api_vsp_run_files_v1\(\):\n)', s)
    if m2 and "import re" not in s[m2.end():m2.end()+300]:
        s = s[:m2.end()] + "    import re\n" + s[m2.end():]
        changed += 1

p.write_text(s, encoding="utf-8")
print("[OK] patched:", changed, "change(s)")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
else
  # still try restart; service might be in failed state
  sudo systemctl restart "$SVC" || true
  echo "[INFO] attempted restart (service may have been failed)"
fi

echo "== status (top) =="
systemctl status "$SVC" --no-pager -l | head -n 40 || true
