#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_defaultdl_${TS}"
echo "[BACKUP] ${F}.bak_defaultdl_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_runs_reports_bp.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_RUN_FILE_DEFAULT_DOWNLOAD_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

# Find api_run_file block and replace return send_file(...) with default-download behavior
m = re.search(r'@bp\.get\("/api/vsp/run_file"\)\s*\n(def\s+api_run_file\(\)\s*:\s*\n)', s)
if not m:
    raise SystemExit("[ERR] cannot find api_run_file handler")

# Replace any existing want_dl + return send_file(...) OR plain return send_file(...)
# 1) remove any prior want_dl assignment lines we injected before
s = re.sub(r'(?m)^\s*want_dl\s*=.*\n', '', s)

# 2) replace last return send_file(str(rp)... ) inside handler
pat = r'(?m)^\s*return\s+send_file\s*\(\s*str\s*\(\s*rp\s*\)\s*(?:,[^\n]*)?\)\s*$'
repl = (
'    # '+MARK+': default download for non-HTML reports\n'
'    q = (request.args.get("download","") or "").strip().lower()\n'
'    want_dl = True if rel != "reports/index.html" else False\n'
'    if q in ("0","false","no","n"): want_dl = False\n'
'    if q in ("1","true","yes","y"): want_dl = True\n'
'    return send_file(str(rp), as_attachment=want_dl, download_name=rp.name)\n'
)

s2, n = re.subn(pat, repl, s, count=1)
if n != 1:
    raise SystemExit("[ERR] cannot patch return send_file(str(rp)) line (pattern mismatch)")

p.write_text(s2 + f"\n# {MARK}\n", encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | python3 -c 'import sys,json; print(json.load(sys.stdin)["items"][0]["run_id"])')"
echo "RID=$RID"

echo "== smoke: JSON should download (Content-Disposition: attachment) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/findings_unified.json" | egrep -i "HTTP/|Content-Disposition|Content-Type" | head -n 12
