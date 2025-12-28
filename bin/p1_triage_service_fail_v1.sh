#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== status =="
sudo systemctl --no-pager -l status vsp-ui-8910.service || true

echo
echo "== journal (last 200) =="
sudo journalctl -xeu vsp-ui-8910.service --no-pager -n 200 || true

echo
echo "== py_compile key entrypoints =="
python3 -m py_compile wsgi_vsp_ui_gateway.py vsp_demo_app.py vsp_runs_reports_bp.py

echo
echo "== py_compile all non-backup py (quick scan) =="
python3 - <<'PY'
from pathlib import Path
import sys
bad=[]
skip_markers=(".bak_", "_trash_py_", "old_", "bak_v", ".bak")
for fp in Path(".").rglob("*.py"):
    s=str(fp)
    if any(m in s for m in skip_markers): 
        continue
    try:
        import py_compile
        py_compile.compile(str(fp), doraise=True)
    except Exception as e:
        bad.append((s, repr(e)))
print("bad=", len(bad))
for s,e in bad[:50]:
    print(" -", s, e)
if bad:
    sys.exit(2)
PY

echo
echo "== tail boot/error logs =="
tail -n 80 out_ci/ui_8910.boot.log 2>/dev/null || true
echo "----"
tail -n 80 out_ci/ui_8910.error.log 2>/dev/null || true
