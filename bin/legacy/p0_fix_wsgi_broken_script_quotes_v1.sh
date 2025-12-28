#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_fix_script_quotes_${TS}"
echo "[BACKUP] ${W}.bak_fix_script_quotes_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

w = Path("wsgi_vsp_ui_gateway.py")
lines = w.read_text(encoding="utf-8", errors="replace").splitlines(True)

n_fix = 0

for i, ln in enumerate(lines):
    s = ln

    # target: any line that contains <script ... src="/static/js/...">
    if "<script" not in s or 'src="/static/js/' not in s:
        continue

    # extract src path safely from raw text (even if python quoting is broken)
    m = re.search(r'src="(/static/js/[^"]+)"', s)
    if not m:
        continue
    src = m.group(1)

    # keep indentation and trailing comma if present
    indent = s[:len(s) - len(s.lstrip(" \t"))]
    suffix = "," if s.rstrip().endswith(",") else ""

    # Rewrite the whole line into a safe single-quoted python string line
    # Always include newline \n in the string, because these blocks usually join lines.
    new_line = f"{indent}'  <script src=\"{src}\"></script>\\n'{suffix}\n"

    # Only rewrite if the line looks suspicious (broken quoting) OR is double-quoted at start
    # (line 325 case: starts with " then contains src=" which breaks python string)
    if s.lstrip().startswith('"') or ("<script" in s and 'src="/static/js/' in s):
        lines[i] = new_line
        n_fix += 1

w.write_text("".join(lines), encoding="utf-8")
print(f"[OK] rewrote broken <script src> lines: {n_fix}")
PY

echo "== py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== restart service =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== sanity =="
curl -sS -I "$BASE/" | sed -n '1,8p' || true
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo

echo "[DONE] If OK: hard reload /runs (Ctrl+Shift+R)."
