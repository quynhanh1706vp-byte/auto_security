#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"

TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"
if [ ! -f "$TPL" ]; then
  TPL="$UI_ROOT/templates/vsp_5tabs_full.html"
fi

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template Dashboard 5 tab (vsp_dashboard_2025.html / vsp_5tabs_full.html)"
  exit 1
fi

BACKUP="${TPL}.bak_runs_force_v3_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

export TPL

python - << 'PY'
import os, pathlib

tpl = pathlib.Path(os.environ["TPL"])
html = tpl.read_text(encoding="utf-8")

marker = 'id="vsp-tab-runs"'
i = html.find(marker)
if i == -1:
    print("[ERR] Không thấy id=\"vsp-tab-runs\" trong", tpl)
    raise SystemExit(1)

# chèn container #vsp-runs-root ngay sau dấu '>' của div vsp-tab-runs (nếu chưa có)
j = html.find('>', i)
if j == -1:
    print("[ERR] Không tìm được '>' sau vsp-tab-runs trong", tpl)
    raise SystemExit(1)

inject = """
  <div id="vsp-runs-root" class="vsp-card vsp-card-soft" style="margin-top:1.5rem;">
    <div class="vsp-empty">
      <div class="vsp-empty-title">Đang tải Runs &amp; Reports...</div>
      <div class="vsp-empty-subtitle">Vui lòng đợi trong giây lát.</div>
    </div>
  </div>
"""
if 'id="vsp-runs-root"' not in html:
    html = html[:j+1] + inject + html[j+1:]
    print("[OK] Đã inject #vsp-runs-root vào vsp-tab-runs")
else:
    print("[INFO] #vsp-runs-root đã tồn tại – giữ nguyên")

script_tag = '<script src="/static/js/vsp_runs_tab_force_v3.js"></script>'
if script_tag not in html:
    html = html.replace('</body>', f'  {script_tag}\\n</body>')
    print("[OK] Đã gắn script vsp_runs_tab_force_v3.js vào template")
else:
    print("[INFO] Script vsp_runs_tab_force_v3.js đã có – bỏ qua")

tpl.write_text(html, encoding="utf-8")
PY
