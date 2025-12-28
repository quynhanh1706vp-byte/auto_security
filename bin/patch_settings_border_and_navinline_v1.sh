#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/settings.html"
BASE="$ROOT/templates/base.html"
CSS="$ROOT/static/css/security_resilient.css"

# --- 1) Thêm class sb-main-settings để CSS nhận diện trang Settings ---
if [ -f "$TPL" ]; then
  BKP_TPL="$TPL.bak_border_$(date +%Y%m%d_%H%M%S)"
  cp "$TPL" "$BKP_TPL"
  echo "[i] Backup settings.html -> $BKP_TPL"

  python3 - "$TPL" << 'PY'
from pathlib import Path

path = Path(__import__("sys").argv[1])
data = path.read_text(encoding="utf-8")
old = data

# chỉ đổi lần xuất hiện đầu tiên của sb-main
needle = 'class="sb-main"'
if needle in data:
    data = data.replace(needle, 'class="sb-main sb-main-settings"', 1)
    path.write_text(data, encoding="utf-8")
    print("[OK] Thêm sb-main-settings vào settings.html")
else:
    print("[WARN] Không tìm thấy 'class=\"sb-main\"' trong settings.html – bỏ qua")
PY
else
  echo "[WARN] Không tìm thấy $TPL"
fi

# --- 2) CSS: viền rõ cho card bên trong trang Settings ---
if [ -f "$CSS" ]; then
  BKP_CSS="$CSS.bak_border_$(date +%Y%m%d_%H%M%S)"
  cp "$CSS" "$BKP_CSS"
  echo "[i] Backup security_resilient.css -> $BKP_CSS"

  cat >> "$CSS" << 'CSS'


/* SETTINGS PAGE – border rõ cho khung bên trong */
.sb-main-settings .sb-card.sb-card-fill {
  border: 1px solid rgba(148, 163, 184, 0.55);
  box-shadow: 0 0 0 1px rgba(15, 23, 42, 0.85);
}
CSS

  echo "[OK] Đã thêm CSS viền khung cho Settings."
else
  echo "[WARN] Không tìm thấy $CSS"
fi

# --- 3) base.html: ép tab Settings xanh lá khi đang ở /settings ---
if [ -f "$BASE" ]; then
  BKP_BASE="$BASE.bak_settingsnav_$(date +%Y%m%d_%H%M%S)"
  cp "$BASE" "$BKP_BASE"
  echo "[i] Backup base.html -> $BKP_BASE"

  python3 - "$BASE" << 'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")
old = data

needle = '<a href="/settings"'
if needle not in data:
    print("[WARN] Không thấy '<a href=\"/settings\"' trong base.html – không patch được inline style.")
else:
    # chèn điều kiện theo request.path để chỉ tô màu khi đang ở /settings
    data = data.replace(
        needle,
        '<a href="/settings"{% if request.path == "/settings" %} '
        'style="background:#80d36b;border-color:#c5ff9c;color:#04130a;"'
        '{% endif %}'
    )
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn inline style cho /settings trong base.html")
PY
else
  echo "[WARN] Không tìm thấy $BASE"
fi

echo "[DONE] patch_settings_border_and_navinline_v1.sh hoàn thành."
