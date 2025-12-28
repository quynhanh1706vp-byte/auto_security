#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_codeql_statusv2_${TS}"
echo "[BACKUP] $F.bak_codeql_statusv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_STATUSV2_EXPOSE_CODEQL_V1 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Try to insert near gitleaks section in run_status_v2 builder (best-effort)
# We look for "has_gitleaks" assignment and insert after that block.
m = re.search(r'(out\[\s*[\'"]has_gitleaks[\'"]\s*\].*\n.*?out\[\s*[\'"]gitleaks_total[\'"]\s*\].*\n)', t, flags=re.S)
if not m:
    # fallback: insert before final "return jsonify(out)" in run_status_v2 handler
    m = re.search(r'(\n\s*return\s+jsonify\(\s*out\s*\)\s*\n)', t)
    if not m:
        print("[ERR] cannot locate insertion point for status_v2")
        raise SystemExit(2)
    ins = m.start()
else:
    ins = m.end()

block = r'''
# === VSP_STATUSV2_EXPOSE_CODEQL_V1 ===
# Expose CodeQL in status_v2 (so UI can bind without null)
codeql_dir = os.path.join(ci_run_dir, "codeql")
codeql_summary = os.path.join(codeql_dir, "codeql_summary.json")
out["has_codeql"] = False
out["codeql_verdict"] = None
out["codeql_total"] = 0
try:
    if os.path.isfile(codeql_summary):
        j = _read_json_safe(codeql_summary) or {}
        out["has_codeql"] = True
        out["codeql_verdict"] = j.get("verdict") or j.get("overall_verdict")
        out["codeql_total"] = int(j.get("total") or 0)
    else:
        # fallback: if any sarif exists, mark as present (AMBER until summary appears)
        if os.path.isdir(codeql_dir):
            sarifs = [x for x in os.listdir(codeql_dir) if x.lower().endswith(".sarif")]
            if sarifs:
                out["has_codeql"] = True
                out["codeql_verdict"] = out["codeql_verdict"] or "AMBER"
                out["codeql_total"] = out["codeql_total"] or 0
except Exception:
    pass
'''

t2 = t[:ins] + "\n" + block + "\n" + t[ins:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted codeql fields into status_v2")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

# restart 8910 (commercial script)
if [ -x bin/restart_8910_gunicorn_commercial_v5.sh ]; then
  bin/restart_8910_gunicorn_commercial_v5.sh
else
  echo "[WARN] missing restart script; please restart service manually"
fi

echo "== VERIFY =="
CI="$(ls -1dt /home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_* 2>/dev/null | head -n 1)"
RID="RUN_$(basename "$CI")"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{ok, has_codeql, codeql_verdict, codeql_total, has_gitleaks, gitleaks_total, overall_verdict}'
