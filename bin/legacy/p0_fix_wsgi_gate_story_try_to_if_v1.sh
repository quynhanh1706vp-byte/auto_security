#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_try2if_${TS}"
echo "[BACKUP] ${W}.bak_try2if_${TS}"

python3 - <<'PY'
from pathlib import Path

w = Path("wsgi_vsp_ui_gateway.py")
lines = w.read_text(encoding="utf-8", errors="replace").splitlines(True)

def is_try(line: str) -> bool:
    return line.strip() == "try:"

changed = 0
# Strategy A: for each marker, convert nearest preceding "try:" within 40 lines
for i, ln in enumerate(lines):
    if "VSP_P1_GATE_STORY_PANEL_V1" in ln:
        for j in range(i-1, max(-1, i-41), -1):
            if is_try(lines[j]):
                indent = lines[j][:len(lines[j]) - len(lines[j].lstrip())]
                lines[j] = indent + "if True:  # VSP_PATCH_TRY2IF_GATE_STORY_V1\n"
                changed += 1
                break

# Strategy B: also cover the exact gate_story script include area (if present)
needle = "vsp_dashboard_gate_story_v1.js"
for i, ln in enumerate(lines):
    if needle in ln:
        for j in range(i-1, max(-1, i-16), -1):
            if is_try(lines[j]):
                indent = lines[j][:len(lines[j]) - len(lines[j].lstrip())]
                if "VSP_PATCH_TRY2IF_GATE_STORY_V1" not in lines[j]:
                    lines[j] = indent + "if True:  # VSP_PATCH_TRY2IF_GATE_STORY_V1\n"
                    changed += 1
                break

w.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched try->if around gate story. changes={changed}")
PY

echo "== py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== sanity =="
curl -sS -I "$BASE/" | sed -n '1,6p' || true
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo

echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
