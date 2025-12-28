#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSS_FILE="$ROOT/static/css/vsp_ui_layout.css"

if [ ! -f "$CSS_FILE" ]; then
  echo "[ERR] Không tìm thấy $CSS_FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${CSS_FILE}.bak_tabs_toggle_${TS}"
cp "$CSS_FILE" "$BACKUP"
echo "[BACKUP] $CSS_FILE -> $BACKUP"

cat >> "$CSS_FILE" << 'CSS_EOF'

/* === VSP MAIN TABS – SIMPLE SWITCH v1 === */

.vsp-tabs-nav {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 14px;
}

.vsp-tab-link {
  border-radius: 999px;
  border: 1px solid rgba(148, 163, 184, 0.45);
  background: rgba(15, 23, 42, 0.92);
  padding: 6px 14px;
  font-size: 12px;
  color: #e5e7eb;
  cursor: pointer;
}

.vsp-tab-link:hover {
  background: rgba(30, 64, 175, 0.9);
}

.vsp-tab-link-active {
  background: linear-gradient(
    90deg,
    rgba(56, 189, 248, 0.35),
    rgba(16, 185, 129, 0.35)
  );
  border-color: rgba(56, 189, 248, 0.9);
}

/* Ẩn/hiện panes */
.vsp-tab-pane {
  display: none;
}

.vsp-tab-pane.vsp-tab-pane-active {
  display: block;
}
CSS_EOF

echo "[OK] Appended tab toggle CSS."
