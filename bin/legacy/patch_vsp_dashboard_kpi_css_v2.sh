#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"
BACKUP="$TPL.bak_kpi_css_v2_$(date +%Y%m%d_%H%M%S)"

echo "[BACKUP] $TPL -> $BACKUP"
cp "$TPL" "$BACKUP"

python - << 'PY'
import pathlib, re

tpl_path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl_path.read_text(encoding="utf-8")

backup = tpl_path.with_suffix(".html.bak_kpi_css_v2_inner")
backup.write_text(txt, encoding="utf-8")
print("[BACKUP_INNER]", backup)

pat = r"(\.vsp-kpi-card__value\s*\{[^}]*\})"
m = re.search(pat, txt, re.S)
if not m:
    print("[WARN] Không tìm thấy block .vsp-kpi-card__value – không patch được.")
else:
    block = m.group(1)
    if "text-overflow" in block:
        print("[INFO] .vsp-kpi-card__value đã có ellipsis – giữ nguyên.")
    else:
        idx = block.rfind("}")
        extra = """
      max-width: 260px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;"""
        new_block = block[:idx] + extra + block[idx:]
        txt = txt.replace(block, new_block)
        tpl_path.write_text(txt, encoding="utf-8")
        print("[PATCH] Đã thêm ellipsis cho .vsp-kpi-card__value.")
PY

echo "[DONE] patch_vsp_dashboard_kpi_css_v2.sh hoàn tất."
