#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[PATCH_VSP_RUNS_TAB_TEMPLATE_V1]"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CANDIDATES=(
  "templates/vsp_5tabs_full.html"
  "templates/vsp_dashboard_2025.html"
  "templates/vsp_layout_sidebar.html"
)

patch_done=0

for tpl in "${CANDIDATES[@]}"; do
  if [ ! -f "$tpl" ]; then
    echo "$LOG_PREFIX [INFO] Bỏ qua $tpl (không tồn tại)"
    continue
  fi

  if ! grep -q 'id="vsp-tab-runs"' "$tpl"; then
    echo "$LOG_PREFIX [INFO] Bỏ qua $tpl (không có vsp-tab-runs)"
    continue
  fi

  ts="$(date +%Y%m%d_%H%M%S)"
  backup="${tpl}.bak_runs_tab_simple_${ts}"
  cp "$tpl" "$backup"
  echo "$LOG_PREFIX [BACKUP] $tpl -> $backup"

  python - << PY
import pathlib

LOG_PREFIX = "$LOG_PREFIX"
tpl_path = pathlib.Path("$tpl")
txt = tpl_path.read_text(encoding="utf-8")

changed = False

# 1) Thêm container #vsp-runs-overview bên trong #vsp-tab-runs nếu chưa có
if 'id="vsp-runs-overview"' not in txt:
    idx = txt.find('id="vsp-tab-runs"')
    if idx != -1:
        # Tìm dấu '>' của thẻ <div ... id="vsp-tab-runs"...>
        gt_idx = txt.find('>', idx)
        if gt_idx != -1:
            inject = '\\n    <div id="vsp-runs-overview"></div>'
            txt = txt[:gt_idx+1] + inject + txt[gt_idx+1:]
            print(LOG_PREFIX, "[OK] Đã inject <div id=\\"vsp-runs-overview\\"> vào", "$tpl")
            changed = True

# 2) Thêm script vsp_runs_tab_simple_v1.js trước </body> nếu chưa có
if 'vsp_runs_tab_simple_v1.js' not in txt:
    script_tag = '\\n    <script src="{{ url_for(\\'static\\', filename=\\'js/vsp_runs_tab_simple_v1.js\\') }}"></script>'
    body_idx = txt.lower().rfind("</body>")
    if body_idx != -1:
        txt = txt[:body_idx] + script_tag + "\\n" + txt[body_idx:]
        print(LOG_PREFIX, "[OK] Đã inject script vsp_runs_tab_simple_v1.js vào", "$tpl")
        changed = True

if changed:
    tpl_path.write_text(txt, encoding="utf-8")
else:
    print(LOG_PREFIX, "[INFO] Không cần thay đổi", "$tpl")
PY

  patch_done=1
done

if [ "$patch_done" -eq 0 ]; then
  echo "$LOG_PREFIX [WARN] Không patch được template nào (không tìm thấy file chứa vsp-tab-runs)."
else
  echo "$LOG_PREFIX Hoàn tất patch template."
fi
