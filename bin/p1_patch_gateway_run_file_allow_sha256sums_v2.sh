#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_runfile_sha_${TS}"
echo "[BACKUP] ${GW}.bak_runfile_sha_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_GW_RUN_FILE_ALLOW_SHA256SUMS_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# find the route decorator for /api/vsp/run_file in gateway
m_route = re.search(r'@app\.(?:get|route)\(\s*[\'"]\/api\/vsp\/run_file[\'"][^\)]*\)\s*[\r\n]+', s)
if not m_route:
    raise SystemExit('[ERR] cannot find @app.get("/api/vsp/run_file") in wsgi_vsp_ui_gateway.py')

# find the def right after that decorator
m_def = re.search(r'\s*def\s+([a-zA-Z_]\w*)\s*\(\s*\)\s*:\s*[\r\n]+', s[m_route.end():])
if not m_def:
    raise SystemExit("[ERR] cannot find handler def after run_file route")

def_start = m_route.end() + m_def.start()
def_line_end = s.find("\n", def_start)
if def_line_end < 0:
    raise SystemExit("[ERR] unexpected EOF near handler def")

inject = f'''
    # {MARK}: allow reports/SHA256SUMS.txt BEFORE any allowlist/proxy (commercial audit)
    try:
        _rid = (request.args.get("rid","") or request.args.get("run_id","") or request.args.get("run","") or "").strip()
        _rel = (request.args.get("name","") or request.args.get("path","") or request.args.get("rel","") or "").strip().lstrip("/")
        if _rid and _rel == "reports/SHA256SUMS.txt":
            from pathlib import Path as _P
            from flask import send_file as _send_file, jsonify as _jsonify
            _roots = [
                _P("/home/test/Data/SECURITY_BUNDLE/out"),
                _P("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                _P("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
                _P("/home/test/Data/SECURITY_BUNDLE/ui/out"),
            ]
            for _root in _roots:
                _fp = _root / _rid / "reports" / "SHA256SUMS.txt"
                if _fp.exists():
                    return _send_file(str(_fp), as_attachment=True)
            return _jsonify({{"ok": False, "error": "NO_FILE"}}), 404
    except Exception:
        pass
'''

# insert right after the def line (guaranteed earliest)
s2 = s[:def_line_end+1] + inject + s[def_line_end+1:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected at start of gateway run_file handler:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK: wsgi_vsp_ui_gateway.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="btl86-connector_RUN_20251127_095755_000599"
echo "RID=$RID"
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 25
