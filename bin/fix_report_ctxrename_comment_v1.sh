#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
APP="vsp_demo_app.py"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "$APP.bak_fix_ctxcomment_${TS}" && echo "[BACKUP] $APP.bak_fix_ctxcomment_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

if "/*VSP_REPORT_CTX_RENAME_V1*/" not in s:
    print("[WARN] marker not found, nothing to fix")
else:
    s = s.replace("/*VSP_REPORT_CTX_RENAME_V1*/", "# VSP_REPORT_CTX_RENAME_V1", 1)
    p.write_text(s, encoding="utf-8")
    print("[OK] replaced C-style comment with Python comment")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] fix_report_ctxrename_comment_v1"
