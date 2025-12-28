#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_anchor_sha_${TS}"
echo "[BACKUP] ${GW}.bak_anchor_sha_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_GW_RUNFILE_ANCHOR_ALLOW_SHA_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

idx = s.find("/api/vsp/run_file")
if idx < 0:
    raise SystemExit("[ERR] cannot find '/api/vsp/run_file' string in gateway")

# find the next "def <name>(" after the anchor (handler def)
m = re.search(r'\n\s*def\s+\w+\s*\([^)]*\)\s*:\s*\n', s[idx:])
if not m:
    raise SystemExit("[ERR] cannot find handler def after /api/vsp/run_file anchor")

def_start = idx + m.start()
def_line_end = s.find("\n", def_start)
if def_line_end < 0:
    raise SystemExit("[ERR] unexpected EOF near def")

inject = f'''    # {MARK}: allow reports/SHA256SUMS.txt BEFORE any allowlist/proxy
    try:
        from flask import request as _req, send_file as _send_file, jsonify as _jsonify
        _rid = (_req.args.get("rid","") or _req.args.get("run_id","") or _req.args.get("run","") or "").strip()
        _rel = (_req.args.get("name","") or _req.args.get("path","") or _req.args.get("rel","") or "").strip().lstrip("/")
        if _rid and _rel == "reports/SHA256SUMS.txt":
            from pathlib import Path as _P
            for _root in (
                _P("/home/test/Data/SECURITY_BUNDLE/out"),
                _P("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                _P("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
                _P("/home/test/Data/SECURITY_BUNDLE/ui/out"),
            ):
                _fp = _root / _rid / "reports" / "SHA256SUMS.txt"
                if _fp.exists():
                    return _send_file(str(_fp), as_attachment=True)
            return _jsonify({{"ok": False, "error": "NO_FILE"}}), 404
    except Exception:
        pass

'''

s2 = s[:def_line_end+1] + inject + s[def_line_end+1:] + f"\n# {MARK}\n"
p.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK: wsgi_vsp_ui_gateway.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="btl86-connector_RUN_20251127_095755_000599"
echo "RID=$RID"
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 25
