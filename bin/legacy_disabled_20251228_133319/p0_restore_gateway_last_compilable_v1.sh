#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== find last compilable backup =="
python3 - <<'PY'
from pathlib import Path
import sys

p=Path("wsgi_vsp_ui_gateway.py")
baks=sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"),
            key=lambda x: x.stat().st_mtime, reverse=True)

if not baks:
    print("[ERR] no backups found")
    sys.exit(2)

for bak in baks[:2000]:
    try:
        txt=bak.read_text(encoding="utf-8", errors="replace")
        compile(txt, str(bak), "exec")
        p.write_text(txt, encoding="utf-8")
        print("[OK] restored compilable backup:", bak.name)
        sys.exit(0)
    except SyntaxError:
        continue
    except Exception:
        continue

print("[ERR] no compilable backup found in scanned set")
sys.exit(3)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh
