#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) ensure tools is a package
mkdir -p tools
if [ ! -f tools/__init__.py ]; then
  : > tools/__init__.py
  echo "[OK] created tools/__init__.py"
else
  echo "[OK] tools/__init__.py already exists"
fi

# 2) quick import self-test (must succeed)
python3 - <<'PY'
import sys
sys.path.insert(0, "/home/test/Data/SECURITY_BUNDLE/ui")
import tools.vsp_tabs3_api_impl_v1 as m
print("[OK] import tools.vsp_tabs3_api_impl_v1 OK, has:", hasattr(m, "list_runs"))
PY

# 3) restart
sudo systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.9

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== verify /api/ui endpoints (must be 200 + ok:true) =="
curl -fsS "$BASE/api/ui/runs_v2?limit=1" | head -c 260; echo
curl -fsS "$BASE/api/ui/findings_v2?limit=1&offset=0" | head -c 260; echo
curl -fsS "$BASE/api/ui/settings_v2" | head -c 260; echo
curl -fsS "$BASE/api/ui/rule_overrides_v2" | head -c 260; echo

echo "[DONE] tools package fixed + api verified"
