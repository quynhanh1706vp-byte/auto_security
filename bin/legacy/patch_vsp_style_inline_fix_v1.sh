#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL" >&2
  exit 1
fi

# Nếu đã chèn rồi thì thôi
if grep -q "VSP_LFIX_V1" "$TPL"; then
  echo "[INFO] Inline layout fix V1 đã tồn tại – skip."
  exit 0
fi

BACKUP="$TPL.bak_style_fix_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

python - << 'PY'
import pathlib, re, sys

tpl = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8")

m = re.search(r"</style>", txt, re.IGNORECASE)
if not m:
    print("[ERR] Không tìm thấy </style> trong vsp_dashboard_2025.html", file=sys.stderr)
    sys.exit(1)

extra_css = r"""
  /* ========== VSP_LFIX_V1 – inline layout fix ========== */

  /* 1) Data Source mini charts: giảm chiều cao, tránh block màu chiếm cả màn */
  #vsp-tab-datasource canvas {
    height: 260px !important;
    max-height: 260px !important;
  }
  #vsp-tab-datasource [class*="chart"],
  #vsp-tab-datasource .chart-container,
  #vsp-tab-datasource .chartjs-render-monitor {
    height: auto !important;
    max-height: 280px !important;
    overflow: hidden;
  }

  /* 2) Card Data Source mini charts có khoảng cách rõ hơn với phần còn lại */
  #vsp-tab-datasource .vsp-card {
    margin-bottom: 16px;
  }

  /* 3) Settings & Rule overrides: bó hẹp chiều ngang cho giống giao diện thương mại */
  #vsp-tab-settings > div,
  #vsp-tab-overrides > div {
    max-width: 1100px;
    margin-left: auto;
    margin-right: auto;
  }

  /* 4) Bảng Data Source & Runs: đỡ dính sát mép dưới màn hình */
  #vsp-tab-datasource table,
  #vsp-tab-runs table {
    font-size: 12px;
  }
  #vsp-tab-datasource table th,
  #vsp-tab-datasource table td,
  #vsp-tab-runs table th,
  #vsp-tab-runs table td {
    padding: 7px 10px;
  }
"""

new_txt = txt[:m.start()] + extra_css + "\n" + txt[m.start():]
tpl.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã chèn inline CSS layout fix V1 (VSP_LFIX_V1) vào vsp_dashboard_2025.html")
PY

echo "[DONE] Inline style fix V1 đã được apply."
