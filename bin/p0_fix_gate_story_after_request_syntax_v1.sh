#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_gate_story_syntax_${TS}"
echo "[BACKUP] ${W}.bak_gate_story_syntax_${TS}"

python3 - <<'PY'
from pathlib import Path

w = Path("wsgi_vsp_ui_gateway.py")
lines = w.read_text(encoding="utf-8", errors="replace").splitlines(True)

def find_func_start(name: str):
    for i, ln in enumerate(lines):
        if ln.startswith("def "+name) or ("def "+name) in ln:
            return i
    return -1

# find the gate-story after_request function
start = -1
for i, ln in enumerate(lines):
    if ln.strip().startswith("def _vsp_p1_gate_story_after_request_v1"):
        start = i
        break

if start < 0:
    raise SystemExit("[ERR] cannot locate _vsp_p1_gate_story_after_request_v1")

end = min(len(lines), start + 260)

changed_try = 0
changed_html = 0
changed_script = 0

for i in range(start, end):
    s = lines[i]

    # 1) if True patch -> try (must match except below)
    if "VSP_PATCH_TRY2IF_GATE_STORY_V1" in s and "if True" in s:
        indent = s[:len(s) - len(s.lstrip())]
        lines[i] = indent + "try:  # VSP_P1_GATE_STORY_TRY_V1\n"
        changed_try += 1
        continue

    # 2) remove stray HTML marker line that breaks Python
    st = s.lstrip()
    if st.startswith("<!--") and "VSP_P1_GATE_STORY_PANEL_V1" in s:
        indent = s[:len(s) - len(s.lstrip())]
        lines[i] = indent + "# VSP_P1_GATE_STORY_PANEL_V1\n"
        changed_html += 1
        continue

    # also catch the weird tail "'\n" on that marker line
    if "VSP_P1_GATE_STORY_PANEL_V1" in s and ("<!--" in s or st.startswith("<")):
        indent = s[:len(s) - len(s.lstrip())]
        lines[i] = indent + "# VSP_P1_GATE_STORY_PANEL_V1\n"
        changed_html += 1
        continue

    # 3) make script include safe (no jinja token inside python string)
    if "script =" in s and "vsp_dashboard_gate_story_v1.js" in s and "{{" in s:
        indent = s[:len(s) - len(s.lstrip())]
        lines[i] = indent + "script = '<script src=\"/static/js/vsp_dashboard_gate_story_v1.js\"></script>'\n"
        changed_script += 1
        continue

w.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched gate_story: try_fix={changed_try} html_fix={changed_html} script_fix={changed_script}")
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
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 240; echo

echo "[DONE] Open /runs and hard reload (Ctrl+Shift+R)."
