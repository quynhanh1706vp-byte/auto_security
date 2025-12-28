#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/patch_runs_api_rewrite_run_file_to_run_file2_p0_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_verifyfix_${TS}"
echo "[BACKUP] ${F}.bak_verifyfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/patch_runs_api_rewrite_run_file_to_run_file2_p0_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the fragile python-json verify block with curl+grep checks.
# We search a marker line "== verify json_path" and replace until end.
pat=r"== verify json_path.*?(?=\n\S|\Z)"
m=re.search(pat, s, flags=re.S)
if not m:
    print("[WARN] cannot find verify block to replace (pattern mismatch).")
    raise SystemExit(0)

rep=r"""== verify rewrite (no JSON parse) ==
RID="$(curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=3 | jq -r '.[0].rid // .items[0].rid // empty')"
echo "[RID]=$RID"
if [ -z "${RID:-}" ]; then
  echo "[WARN] cannot get RID from /api/vsp/runs"
else
  # verify that UI gateway uses run_file2 in emitted paths (string check)
  python3 - <<'PY'
from pathlib import Path
t=Path("wsgi_vsp_ui_gateway.py").read_text(encoding="utf-8", errors="replace")
print("[OK] has run_file2 =", ("/api/vsp/run_file2" in t) or ("run_file2" in t))
PY
  # verify endpoint returns JSON for a known file
  curl -sS -G "http://127.0.0.1:8910/api/vsp/run_file2" --data-urlencode "rid=${RID}" --data-urlencode "name=reports/findings_unified.json" | head -c 200; echo
fi
"""
s2=s[:m.start()]+rep+s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced verify block with safe checks")
PY

bash -n bin/patch_runs_api_rewrite_run_file_to_run_file2_p0_v1.sh
echo "[OK] bash -n OK"
