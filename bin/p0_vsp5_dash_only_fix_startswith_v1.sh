#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_startswithfix_${TS}"
echo "[BACKUP] ${JS}.bak_startswithfix_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

before = s.count(".startswith(")
s = s.replace(".startswith(", ".startsWith(")

after = s.count(".startswith(")
p.write_text(s, encoding="utf-8")

print(f"[OK] replaced .startswith( -> .startsWith( : {before} occurrences, remaining={after}")
PY

echo "== restart service (best effort) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
fi

echo "== verify =="
grep -n "\.startswith(" -n "$JS" || echo "OK: no .startswith left"
