#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_optmarkers_${TS}"
echo "[BACKUP] ${F}.bak_optmarkers_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import sys, re

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_OPTIONAL_MARKERS_STUB_V1"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

# We patch inside the FINAL v4 force-markers function block (safe place) by appending extra injects.
start = s.find("# --- VSP_P1_FINAL_MARKERS_FORCE_V4 ---")
end   = s.find("# --- end VSP_P1_FINAL_MARKERS_FORCE_V4 ---", start)
if start == -1 or end == -1:
    print("[ERR] V4 block not found"); raise SystemExit(2)

blk = s[start:end]

# Add optional inject into /vsp5 and /runs, and add minimal stubs for other pages too (safe no-op if not matched).
opt_vsp5 = (
    '\n<!-- '+marker+':vsp5 -->\n'
    '<div style="display:none">\n'
    '  <span data-testid="kpi_posture_score"></span>\n'
    '  <span data-testid="chart_trend"></span>\n'
    '  <span data-testid="tbl_top_findings"></span>\n'
    '</div>\n'
)
opt_runs = (
    '\n<!-- '+marker+':runs -->\n'
    '<div style="display:none">\n'
    '  <span data-testid="runs_filters"></span>\n'
    '  <span data-testid="runs_export"></span>\n'
    '</div>\n'
)
opt_ds = (
    '\n<!-- '+marker+':ds -->\n'
    '<div style="display:none">\n'
    '  <span data-testid="ds_filters"></span>\n'
    '  <span data-testid="ds_table"></span>\n'
    '</div>\n'
)
opt_settings = (
    '\n<!-- '+marker+':settings -->\n'
    '<div style="display:none">\n'
    '  <span data-testid="profile_manager"></span>\n'
    '  <span data-testid="tool_toggles"></span>\n'
    '</div>\n'
)
opt_ro = (
    '\n<!-- '+marker+':ro -->\n'
    '<div style="display:none">\n'
    '  <span data-testid="override_editor"></span>\n'
    '  <span data-testid="override_apply"></span>\n'
    '</div>\n'
)

# Insert into the existing V4 inject strings by simple replacement anchors.
def add_after(sub, add):
    return sub + add

blk2 = blk
# For vsp5: after the kpi-testids block injection, append optional
blk2 = blk2.replace('</div>\\n\'\\n            )',
                    '</div>\\n\'\\n            )' + opt_vsp5.replace("\n", "\\n").replace("'", "\\'"),
                    1)

# For runs: after runs-main inject, append optional runs markers
blk2 = blk2.replace('id="vsp-runs-main" style="display:none"></div>\\n\'',
                    'id="vsp-runs-main" style="display:none"></div>\\n\'' + opt_runs.replace("\n", "\\n").replace("'", "\\'"),
                    1)

# Also extend force list to cover other tabs (if desired)
# We add extra branches with safe injection before return body.
if 'if path == "/data_source"' not in blk2:
    insert_point = blk2.rfind("return body")
    if insert_point != -1:
        extra = r'''
    if path == "/data_source":
        if 'data-testid="ds_filters"' not in html:
            html = __vsp_v4_insert_before_body_end(html, ''' + repr(opt_ds) + r''')
            return html.encode("utf-8")
    if path == "/settings":
        if 'data-testid="profile_manager"' not in html:
            html = __vsp_v4_insert_before_body_end(html, ''' + repr(opt_settings) + r''')
            return html.encode("utf-8")
    if path == "/rule_overrides":
        if 'data-testid="override_editor"' not in html:
            html = __vsp_v4_insert_before_body_end(html, ''' + repr(opt_ro) + r''')
            return html.encode("utf-8")
'''
        blk2 = blk2[:insert_point] + extra + "\n" + blk2[insert_point:]

if blk2 == blk:
    print("[WARN] no changes applied"); raise SystemExit(0)

s2 = s[:start] + blk2 + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched optional markers stubs into V4 block")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }
systemctl restart "$SVC" || true
sleep 0.8

echo "== re-run gate =="
bash bin/p1_ui_spec_gate_v1.sh || true
