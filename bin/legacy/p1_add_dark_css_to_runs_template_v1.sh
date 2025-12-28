#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

F="templates/vsp_runs_reports_v1.html"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_addcss_${TS}"
echo "[BACKUP] ${F}.bak_addcss_${TS}"

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

css_href="/static/css/vsp_dark_commercial_p1_2.css"
if css_href in s:
    print("[OK] CSS already present")
    raise SystemExit(0)

# inject before </head>
link = f'<link rel="stylesheet" href="{css_href}">'
if "</head>" not in s:
    print("[ERR] </head> not found; cannot inject safely")
    raise SystemExit(2)

s = s.replace("</head>", link + "\n</head>", 1)
p.write_text(s, encoding="utf-8")
print("[OK] injected commercial dark CSS into runs template")
PY

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

echo "== verify /runs contains CSS link =="
curl -fsS "$BASE/runs" | grep -oE '/static/css/[^"'\'' >]+' | sed 's/[?].*$//' | sort -u
