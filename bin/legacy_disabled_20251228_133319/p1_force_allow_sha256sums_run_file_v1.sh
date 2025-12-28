#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

patch_one(){
  local F="$1"
  [ -f "$F" ] || return 0
  local TS
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$F" "${F}.bak_force_sha_${TS}"
  echo "[BACKUP] ${F}.bak_force_sha_${TS}"

  python3 - <<PY
from pathlib import Path
import re

p=Path("$F")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_FORCE_ALLOW_SHA256SUMS_RUN_FILE_V1"
if MARK in s:
    print("[OK] already patched:", p.name)
    raise SystemExit(0)

# Find a /api/vsp/run_file handler in this file (best-effort)
idx = s.find("/api/vsp/run_file")
if idx < 0:
    print("[SKIP] no /api/vsp/run_file in", p.name)
    raise SystemExit(0)

mdef = re.search(r'\n\s*def\s+\w+\s*\([^)]*\)\s*:\s*\n', s[idx:])
if not mdef:
    raise SystemExit("[ERR] cannot locate handler def after /api/vsp/run_file in " + p.name)

def_start = idx + mdef.start()
mend = re.search(r'\n(?:@|def)\s', s[def_start+1:])  # next decorator/def (good enough)
def_end = (def_start+1+mend.start()) if mend else len(s)
func = s[def_start:def_end]

# Inject bypass near top of handler (after args parsing if possible, else right after def line)
inject = f'''
    # {MARK}: always allow reports/SHA256SUMS.txt download (commercial audit)
    try:
        _rid = (request.args.get("rid","") or request.args.get("run_id","") or request.args.get("run","") or "").strip()
        _rel = (request.args.get("name","") or request.args.get("path","") or request.args.get("rel","") or "").strip().lstrip("/")
        if _rid and _rel == "reports/SHA256SUMS.txt":
            from pathlib import Path as _P
            from flask import send_file as _send_file, jsonify as _jsonify
            # try common run roots
            _roots = [
                _P("/home/test/Data/SECURITY_BUNDLE/out"),
                _P("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                _P("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
                _P("/home/test/Data/SECURITY_BUNDLE/ui/out"),
            ]
            for _root in _roots:
                _fp = (_root / _rid / "reports" / "SHA256SUMS.txt")
                if _fp.exists():
                    return _send_file(str(_fp), as_attachment=True)
            return _jsonify({{"ok": False, "error": "NO_FILE"}}), 404
    except Exception:
        pass
'''

# Prefer anchor after first rel/name extraction line if present
anchors = [
    r'^\s*rel\s*=\s*.*$',
    r'^\s*name\s*=\s*.*$',
]
pos = None
for ap in anchors:
    m = re.search(ap, func, flags=re.M)
    if m:
        pos = m.end()
        break
if pos is None:
    # insert right after def line
    m = re.search(r'^\s*def\s+\w+\s*\([^)]*\)\s*:\s*$', func, flags=re.M)
    pos = m.end() if m else 0

func2 = func[:pos] + "\n" + inject + func[pos:]
s2 = s[:def_start] + func2 + s[def_end:] + f"\n# {MARK}\n"
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", p.name)
PY

  python3 -m py_compile "$F"
  echo "[OK] py_compile OK: $F"
}

patch_one "vsp_runs_reports_bp.py"
patch_one "vsp_demo_app.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | python3 -c 'import sys,json; print(json.load(sys.stdin)["items"][0]["run_id"])')"
echo "RID=$RID"

echo "== GET sha256sums via rid/name =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 20

echo "== GET sha256sums via run_id/path =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?run_id=$RID&path=reports/SHA256SUMS.txt" | head -n 20
