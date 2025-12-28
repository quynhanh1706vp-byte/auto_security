#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need ls; need head; need awk; need curl

echo "== (1) restore vsp_runs_reports_bp.py from latest good backup =="
B="$(ls -1t vsp_runs_reports_bp.py.bak_p1v7_* vsp_runs_reports_bp.py.bak_* 2>/dev/null | head -n1 || true)"
[ -n "${B:-}" ] || { echo "[ERR] no backup found for vsp_runs_reports_bp.py"; exit 3; }
cp -f "$B" vsp_runs_reports_bp.py
echo "[RESTORED] vsp_runs_reports_bp.py <= $B"

echo "== (2) re-apply minimal safe fixes in bp: tuple-bug + run_file allow SHA256SUMS =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_runs_reports_bp.py")
s=p.read_text(encoding="utf-8", errors="replace")

# fix tuple bug if still present
broken='(run_dir/"SUMMARY.txt" "SHA256SUMS.txt",).exists()'
fixed='((run_dir/"SUMMARY.txt").exists() or (run_dir/"reports/SUMMARY.txt").exists())'
s=s.replace(broken, fixed)

# ensure run_file handler allowlist contains reports/SHA256SUMS.txt and supports rid/name
start=s.find('@bp.get("/api/vsp/run_file")')
if start>=0:
    # find end at "return send_file(str(rp))" within that block
    mend=re.search(r'^[ \t]*return\s+send_file\s*\(\s*str\s*\(\s*rp\s*\)\s*\)\s*$', s[start:], flags=re.M)
    if mend:
        end_pos=start+mend.end()
        nl=s.find("\n", end_pos)
        if nl!=-1: end_pos=nl+1

        new_block = '''@bp.get("/api/vsp/run_file")
def api_run_file():
    """
    Commercial contract:
    - Accept BOTH:
      * rid + name
      * run_id + path
    - Strict allowlist under reports/
    """
    run_id = (request.args.get("run_id","") or request.args.get("rid","") or request.args.get("run","") or "").strip()
    rel    = (request.args.get("path","")   or request.args.get("name","") or request.args.get("rel","") or "").strip()

    if not run_id or not rel:
        return jsonify({"ok": False, "error": "MISSING_PARAMS"}), 400

    rel = rel.lstrip("/")

    ALLOWED = {
        "reports/index.html",
        "reports/run_gate_summary.json",
        "reports/findings_unified.json",
        "reports/SUMMARY.txt",
        "reports/SHA256SUMS.txt",
    }
    if rel not in ALLOWED:
        return jsonify({"ok": False, "err": "not allowed"}), 404

    rd = (OUT_ROOT / run_id).resolve()
    if not rd.exists():
        return jsonify({"ok": False, "error": "NO_SUCH_RUN"}), 404

    rp = (rd / rel).resolve()
    if str(rp).find(str(rd)) != 0:
        return jsonify({"ok": False, "error": "PATH_TRAVERSAL"}), 400
    if (not rp.exists()) or (not rp.is_file()):
        return jsonify({"ok": False, "error": "NO_FILE"}), 404

    return send_file(str(rp))
'''
        s = s[:start] + new_block + "\n" + s[end_pos:]
p.write_text(s, encoding="utf-8")
print("[OK] bp normalized")
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] bp py_compile OK"

echo "== (3) patch wsgi_vsp_ui_gateway.py: bypass not-allowed for SHA256SUMS =="
GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 4; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_allowsha_gw_${TS}"
echo "[BACKUP] ${GW}.bak_allowsha_gw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_GW_BYPASS_SHA256SUMS_V1"
if MARK in s:
    print("[OK] already patched gw")
    raise SystemExit(0)

# inject before first return line that contains "not allowed"
m=re.search(r'^([ \t]*)return[^\n]*not allowed[^\n]*$', s, flags=re.M)
if not m:
    # maybe json payload style
    m=re.search(r'^([ \t]*)return[^\n]*["\']not allowed["\'][^\n]*$', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find not-allowed return in gateway (grep -n \"not allowed\" wsgi_vsp_ui_gateway.py)")

ind=m.group(1)
inject = (
f"{ind}# {MARK}: allow reports/SHA256SUMS.txt (commercial audit)\n"
f"{ind}try:\n"
f"{ind}    _rid = (request.args.get('rid','') or request.args.get('run_id','') or request.args.get('run','') or '').strip()\n"
f"{ind}    _rel = (request.args.get('name','') or request.args.get('path','') or request.args.get('rel','') or '').strip().lstrip('/')\n"
f"{ind}    if _rid and _rel == 'reports/SHA256SUMS.txt':\n"
f"{ind}        from pathlib import Path as _P\n"
f"{ind}        from flask import send_file as _send_file, jsonify as _jsonify\n"
f"{ind}        _fp = _P('/home/test/Data/SECURITY_BUNDLE/out') / _rid / 'reports' / 'SHA256SUMS.txt'\n"
f"{ind}        if _fp.exists():\n"
f"{ind}            return _send_file(str(_fp), as_attachment=True)\n"
f"{ind}        return _jsonify({{'ok': False, 'error': 'NO_FILE'}}), 404\n"
f"{ind}except Exception:\n"
f"{ind}    pass\n"
)

s = s[:m.start()] + inject + s[m.start():] + f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] gateway patched:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] gw py_compile OK"

echo "== (4) restart service =="
sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== (5) smoke =="
curl -sS -I http://127.0.0.1:8910/vsp5 | head -n 5

RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | python3 -c 'import sys,json; print(json.load(sys.stdin)["items"][0]["run_id"])')"
echo "RID=$RID"

curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 25
