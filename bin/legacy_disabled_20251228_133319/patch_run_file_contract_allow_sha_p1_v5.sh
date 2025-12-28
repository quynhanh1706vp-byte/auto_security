#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runfile_p1v5_${TS}"
echo "[BACKUP] ${F}.bak_runfile_p1v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_runs_reports_bp.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RUN_FILE_CONTRACT_ALLOW_SHA_V5"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Replace the whole api_run_file() handler block
pat = r'@bp\.get\("/api/vsp/run_file"\)\s*\ndef\s+api_run_file\s*\(\s*\)\s*:\s*\n(?:[ \t].*\n)+?(?=\n\S|\Z)'
m=re.search(pat, s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot locate api_run_file() block for /api/vsp/run_file")

new = r'''@bp.get("/api/vsp/run_file")
def api_run_file():
    """
    Commercial contract:
    - Accept both styles:
      * rid + name   (legacy UI/exports)
      * run_id + path (bp native)
    - Strict allowlist for reports/*
    """
    rid = (request.args.get("rid","") or request.args.get("run_id","") or request.args.get("run","") or "").strip()
    rel = (request.args.get("name","") or request.args.get("path","") or request.args.get("rel","") or "").strip()

    if not rid or not rel:
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

    rd = (OUT_ROOT / rid).resolve()
    if not rd.exists():
        return jsonify({"ok": False, "error": "NO_SUCH_RUN"}), 404

    rp = (rd / rel).resolve()
    if str(rp).find(str(rd)) != 0:
        return jsonify({"ok": False, "error": "PATH_TRAVERSAL"}), 400
    if (not rp.exists()) or (not rp.is_file()):
        return jsonify({"ok": False, "error": "NO_FILE"}), 404

    return send_file(str(rp))
'''

s2 = s[:m.start()] + new + "\n\n# " + MARK + "\n" + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched run_file handler + allowlist:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="btl86-connector_RUN_20251127_095755_000599"
echo "RID=$RID"

echo "== check run_file with rid/name (legacy) =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 20

echo "== check run_file with run_id/path (native) =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?run_id=$RID&path=reports/SHA256SUMS.txt" | head -n 20

echo "== check /api/vsp/runs not 500 =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/runs?limit=1" | head -n 25
