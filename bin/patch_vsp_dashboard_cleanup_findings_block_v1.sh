#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_cleanup_findings_$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL"
  exit 1
fi

cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

python - << 'PY'
from pathlib import Path
import re

tpl_path = Path("templates/vsp_dashboard_2025.html")
html = tpl_path.read_text(encoding="utf-8")

# 1) Bỏ nguyên block <!-- === DASHBOARD FINDINGS ZONE ... -->
pattern_block = re.compile(
    r"\s*<!-- === DASHBOARD FINDINGS ZONE.*?JS: Dashboard findings renderer.*?vsp_dashboard_findings_v1\.js.*?</script>",
    re.DOTALL | re.IGNORECASE,
)

new_html, n = pattern_block.subn("", html)
print(f"[CLEAN] Removed findings block occurrences: {n}")

# 2) Chỉ phòng khi còn sót tag script đơn lẻ
new_html, n2 = re.subn(
    r'\s*<script\s+src="/static/js/vsp_dashboard_findings_v1\.js"></script>',
    "",
    new_html,
    flags=re.IGNORECASE,
)
print(f"[CLEAN] Removed standalone script tags: {n2}")

tpl_path.write_text(new_html, encoding="utf-8")
print("[DONE] Template cleaned – Dashboard layout về trạng thái trước patch.")
PY

echo "[DONE] patch_vsp_dashboard_cleanup_findings_block_v1 completed."
