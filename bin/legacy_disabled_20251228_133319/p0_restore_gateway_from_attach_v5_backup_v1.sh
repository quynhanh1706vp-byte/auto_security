#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
baks=sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_runs_contract_attach_app_v5_*"),
            key=lambda x: x.stat().st_mtime, reverse=True)
if not baks:
    print("[ERR] no bak_runs_contract_attach_app_v5_* found")
    raise SystemExit(2)
bak=baks[0]
p.write_text(bak.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored:", bak.name)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh
