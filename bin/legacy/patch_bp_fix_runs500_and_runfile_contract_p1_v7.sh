#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p1v7_${TS}"
echo "[BACKUP] ${F}.bak_p1v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_runs_reports_bp.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_BP_FIX_RUNS500_RUNFILE_CONTRACT_V7"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# --- (1) Fix tuple bug in _has() that breaks /api/vsp/runs ---
broken = '(run_dir/"SUMMARY.txt" "SHA256SUMS.txt",).exists()'
fixed  = '((run_dir/"SUMMARY.txt").exists() or (run_dir/"reports/SUMMARY.txt").exists())'
if broken in s:
    s = s.replace(broken, fixed)
    print("[OK] fixed tuple .exists() bug (literal)")
else:
    # regex fallback (in case spacing differs)
    s2 = re.sub(
        r'\(\s*run_dir\s*/\s*([\'"])SUMMARY\.txt\1\s*([\'"])SHA256SUMS\.txt\2\s*,\s*\)\s*\.exists\(\)',
        fixed,
        s,
        flags=re.M
    )
    if s2 != s:
        s = s2
        print("[OK] fixed tuple .exists() bug (regex)")

# --- (2) Replace the run_file handler block (decorator+def+body) ---
start = s.find('@bp.get("/api/vsp/run_file")')
if start < 0:
    raise SystemExit('[ERR] cannot find @bp.get("/api/vsp/run_file")')

# find end at "return send_file(str(rp))" line inside this block
m_end = re.search(r'^[ \t]*return\s+send_file\s*\(\s*str\s*\(\s*rp\s*\)\s*\)\s*$', s[start:], flags=re.M)
if not m_end:
    raise SystemExit('[ERR] cannot find end of run_file block (return send_file(str(rp)))')

# cut until end-of-line after that return
end_pos = start + m_end.end()
nl = s.find("\n", end_pos)
if nl != -1:
    end_pos = nl + 1

new_block = r'''@bp.get("/api/vsp/run_file")
def api_run_file():
    """
    Commercial contract:
    - Accept BOTH styles:
        * rid + name     (legacy UI)
        * run_id + path  (blueprint native)
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

s = s[:start] + new_block + "\n\n# " + MARK + "\n" + s[end_pos:]
p.write_text(s, encoding="utf-8")
print("[OK] patched run_file handler + allowlist:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK: vsp_runs_reports_bp.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== smoke: /api/vsp/runs must be JSON now =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/runs?limit=1" | head -n 30

RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | jq -r '.items[0].run_id // empty' 2>/dev/null || true)"
echo "RID=$RID"

echo "== smoke: run_file legacy rid/name (must be 200) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 8

echo "== smoke: run_file native run_id/path (must be 200) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?run_id=$RID&path=reports/SHA256SUMS.txt" | head -n 8
