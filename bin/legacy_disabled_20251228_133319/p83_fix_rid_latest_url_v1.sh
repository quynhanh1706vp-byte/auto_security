#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need grep; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "== [P83] Fix rid_latest_v3 URL (add '?') =="

HITS="$(grep -RIn --line-number --exclude='*.bak_*' 'rid_latest_v3&' static/js || true)"
if [ -z "$HITS" ]; then
  echo "[OK] no rid_latest_v3& found"
  exit 0
fi

echo "$HITS" | head -n 50

python3 - <<'PY'
from pathlib import Path
import re, datetime
root=Path("static/js")
ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
for p in root.rglob("*.js"):
    s=p.read_text(encoding="utf-8", errors="replace")
    if "rid_latest_v3&" not in s:
        continue
    bak=p.with_name(p.name+f".bak_p83_{ts}")
    bak.write_text(s, encoding="utf-8")
    s2=s.replace("rid_latest_v3&", "rid_latest_v3?")
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched", p, "backup=>", bak)
PY

echo "== [syntax check] =="
node -c static/js/vsp_bundle_tabs5_v1.js
node -c static/js/vsp_runs_quick_actions_v1.js
echo "[DONE] Now Ctrl+Shift+R on /runs and re-check console + RID behavior."
