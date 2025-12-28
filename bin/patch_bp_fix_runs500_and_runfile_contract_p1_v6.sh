#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p1v6_${TS}"
echo "[BACKUP] ${F}.bak_p1v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_runs_reports_bp.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_BP_FIX_RUNS500_RUNFILE_CONTRACT_V6"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# --- (1) Fix tuple bug in _has() causing /api/vsp/runs 500 ---
# Replace the exact broken expression wherever it appears.
broken = '(run_dir/"SUMMARY.txt" "SHA256SUMS.txt",).exists()'
fixed  = '((run_dir/"SUMMARY.txt").exists() or (run_dir/"reports/SUMMARY.txt").exists())'
if broken in s:
    s = s.replace(broken, fixed)
    print("[OK] fixed tuple .exists() bug (literal)")
else:
    # regex fallback
    s2 = re.sub(
        r'\(\s*run_dir\s*/\s*([\'"])SUMMARY\.txt\1\s*([\'"])SHA256SUMS\.txt\2\s*,\s*\)\s*\.exists\(\)',
        fixed,
        s,
        flags=re.M
    )
    if s2 != s:
        s = s2
        print("[OK] fixed tuple .exists() bug (regex)")

# Optional: if _has dict lacks sha256sums, add it (safe additive)
if re.search(r'^\s*"has"\s*:\s*_has\(', s, flags=re.M) and "sha256sums" not in s:
    s = re.sub(
        r'("summary"\s*:\s*[^,\n]+,\s*)',
        r'\1' + '\n        "sha256sums": ((run_dir/"reports/SHA256SUMS.txt").exists() or (run_dir/"SHA256SUMS.txt").exists()),\n',
        s,
        count=1
    )

# --- (2) Replace run_file handler to support BOTH param styles + strict allowlist ---
# Find the block starting at @bp.get("/api/vsp/run_file") and def api_run_file(): ... until "return send_file(...)" line.
m = re.search(
    r'@bp\.get\("/api/vsp/run_file"\)\s*\ndef\s+api_run_file\s*\(\s*\)\s*:\s*\n(?:(?:[ \t].*?\n))*?^[ \t]*return\s+send_file\s*\(.*?\)\s*\n',
    s,
    flags=re.M
)
if not m:
    raise SystemExit('[ERR] cannot locate api_run_file() block. Try: grep -n "def api_run_file" vsp_runs_reports_bp.py')

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

s = s[:m.start()] + new_block + "\n" + s[m.end():]
s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== smoke: runs should be JSON (not 500) =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/runs?limit=1" | head -n 30

RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | jq -r '.items[0].run_id // empty' 2>/dev/null || true)"
echo "RID=$RID"

echo "== smoke: run_file legacy rid/name (must be 200) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 8

echo "== smoke: run_file native run_id/path (must be 200) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?run_id=$RID&path=reports/SHA256SUMS.txt" | head -n 8
