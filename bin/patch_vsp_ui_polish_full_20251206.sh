#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"
echo "[PATCH] Root = $PWD"

python - << 'PY'
from pathlib import Path

css_files = [
    Path("static/css/vsp_ui_layout.css"),
    Path("static/css/vsp_main.css"),
]

patch = r"""
/* =========================================================
 * VSP_LAYOUT_TWEAK_20251206 – polish commercial layout
 * ======================================================= */

/* Gom main content về max 1440px cho đỡ trống, dùng được cho nhiều layout */
.vsp-main,
.vsp-main-layout,
.vsp-content,
.vsp-dashboard-shell {
  max-width: 1440px;
  margin: 0 auto;
  padding: 24px 32px 32px;
}

/* Panel look & feel */
.vsp-panel {
  background: radial-gradient(circle at top left, #0f263c 0, #050816 55%, #02040a 100%);
  border-radius: 18px;
  border: 1px solid rgba(255,255,255,0.04);
  padding: 18px 20px;
  box-shadow: 0 18px 40px rgba(0,0,0,0.65);
}

/* Tables bên trong panel */
.vsp-panel table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.vsp-panel thead tr {
  border-bottom: 1px solid rgba(148,163,184,0.4);
}

.vsp-panel th,
.vsp-panel td {
  padding: 8px 12px;
  text-align: left;
}

.vsp-panel tbody tr:nth-child(even) {
  background-color: rgba(15,23,42,0.55);
}

.vsp-panel tbody tr:hover {
  background-color: rgba(45,212,191,0.12);
  cursor: pointer;
}

/* Empty state cho các ô chưa có data */
.vsp-empty-state {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  min-height: 120px;
  font-size: 13px;
  color: rgba(148,163,184,0.85);
  font-style: italic;
}

/* Thanh filter mock cho Data Source */
.vsp-datasource-filters {
  display: flex;
  gap: 8px;
  align-items: center;
  margin-bottom: 16px;
  font-size: 12px;
  color: rgba(148,163,184,0.85);
}

.vsp-datasource-filters select {
  background: rgba(15,23,42,0.9);
  border-radius: 10px;
  border: 1px solid rgba(148,163,184,0.6);
  padding: 4px 10px;
  color: rgba(226,232,240,0.95);
}

/* Settings / code block raw JSON */
.vsp-settings-title {
  font-size: 14px;
  font-weight: 600;
  margin-bottom: 4px;
}

.vsp-settings-subtitle {
  font-size: 12px;
  color: rgba(148,163,184,0.85);
  margin-bottom: 12px;
}

.vsp-code-block {
  max-height: 520px;
  overflow: auto;
  font-size: 12px;
  line-height: 1.5;
  background: rgba(15,23,42,0.95);
  border-radius: 14px;
  padding: 12px 14px;
  border: 1px solid rgba(148,163,184,0.5);
}
"""

for p in css_files:
    if not p.is_file():
        print("[WARN] Không tìm thấy", p)
        continue

    text = p.read_text(encoding="utf-8")
    if "VSP_LAYOUT_TWEAK_20251206" in text:
        print("[INFO]", p, "đã có block VSP_LAYOUT_TWEAK_20251206 – bỏ qua.")
        continue

    p.write_text(text + patch, encoding="utf-8")
    print("[OK] Đã append block VSP_LAYOUT_TWEAK_20251206 vào", p)
PY
