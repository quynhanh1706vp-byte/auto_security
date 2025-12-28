#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

S="bin/restart_8910_gunicorn_commercial_v5.sh"
[ -f "$S" ] || { echo "[ERR] missing $S"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$S" "$S.bak_root_order_${TS}"
echo "[BACKUP] $S.bak_root_order_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/restart_8910_gunicorn_commercial_v5.sh")
t = p.read_text(encoding="utf-8", errors="ignore")

# 1) Remove existing injected GUNI_BIN block (best-effort)
t = re.sub(r"\n# gunicorn runner \(commercial-safe\)[\s\S]*?fi\s*\n", "\n", t, count=1)

# 2) Ensure ROOT is defined immediately after set -euo pipefail
if "ROOT=" not in t:
    t = re.sub(r"(set -euo pipefail\s*\n)", r"\1\nROOT=\"/home/test/Data/SECURITY_BUNDLE/ui\"\n", t, count=1)

# 3) Insert runner block AFTER ROOT and cd
runner = r'''
# gunicorn runner (commercial-safe)
GUNI_BIN=""
if [ -x "$ROOT/.venv/bin/gunicorn" ]; then
  GUNI_BIN="$ROOT/.venv/bin/gunicorn"
elif command -v gunicorn >/dev/null 2>&1; then
  GUNI_BIN="gunicorn"
else
  GUNI_BIN="python3 -m gunicorn"
fi
'''
# insert after: cd "$ROOT"
if runner.strip() not in t:
    t = re.sub(r'(cd\s+"\$ROOT"\s*\n)', r'\1\n'+runner+'\n', t, count=1)

p.write_text(t, encoding="utf-8")
print("[OK] fixed ROOT order + re-inserted GUNI_BIN after cd $ROOT")
PY

chmod +x "$S"
echo "== head of script =="
nl -ba "$S" | head -n 35
