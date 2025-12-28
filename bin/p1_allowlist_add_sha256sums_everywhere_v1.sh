#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

patch_file(){
  local F="$1"
  [ -f "$F" ] || { echo "[SKIP] missing $F"; return 0; }
  cp -f "$F" "${F}.bak_allowsha_tokens_${TS}"
  echo "[BACKUP] ${F}.bak_allowsha_tokens_${TS}"

  python3 - <<PY
from pathlib import Path
p=Path("$F")
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

# 1) full-path allowlist: add reports/SHA256SUMS.txt after reports/SUMMARY.txt
if "reports/SUMMARY.txt" in s and "reports/SHA256SUMS.txt" not in s:
    s = s.replace('"reports/SUMMARY.txt"', '"reports/SUMMARY.txt", "reports/SHA256SUMS.txt"', 1)
    s = s.replace("'reports/SUMMARY.txt'", "'reports/SUMMARY.txt', 'reports/SHA256SUMS.txt'", 1)

# 2) basename allowlist: add SHA256SUMS.txt after SUMMARY.txt
if "SUMMARY.txt" in s and "SHA256SUMS.txt" not in s:
    s = s.replace('"SUMMARY.txt"', '"SUMMARY.txt", "SHA256SUMS.txt"', 1)
    s = s.replace("'SUMMARY.txt'", "'SUMMARY.txt', 'SHA256SUMS.txt'", 1)

# 3) sometimes allowlist contains "SUMMARY" only (rare) – do nothing (avoid risky edits)

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched tokens in", p.name)
else:
    print("[NOOP] no token patch needed in", p.name)
PY
}

# Patch the usual suspects (safe even if NOOP)
patch_file "wsgi_vsp_ui_gateway.py"
patch_file "vsp_demo_app.py"
patch_file "vsp_runs_reports_bp.py"

echo "== py_compile key runtime files =="
python3 -m py_compile wsgi_vsp_ui_gateway.py vsp_demo_app.py vsp_runs_reports_bp.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="btl86-connector_RUN_20251127_095755_000599"
echo "RID=$RID"

echo "== smoke sha256sums (expect 200) =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 25
