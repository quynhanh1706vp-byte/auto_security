#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSS="$ROOT/static/css/vsp_ui_layout.css"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$CSS" "${CSS}.bak_tabs_layout_${TS}"
echo "[BACKUP] $CSS -> ${CSS}.bak_tabs_layout_${TS}"

cat >> "$CSS" << 'CSS_EOF'

/* === VSP Tabs Layout V1 === */

.vsp-two-col {
  display: grid;
  grid-template-columns: minmax(0, 2.1fr) minmax(0, 1.4fr);
  gap: 18px;
}

.vsp-card {
  background: var(--vsp-surface-soft);
  border-radius: 20px;
  border: 1px solid var(--vsp-border-subtle);
  padding: 14px 16px;
  box-shadow: 0 18px 40px rgba(15, 23, 42, 0.75);
}

.vsp-card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 10px;
}

.vsp-card-header-actions {
  align-items: flex-start;
}

.vsp-card-title {
  font-size: 14px;
  font-weight: 600;
  color: rgba(226, 232, 240, 0.98);
}

.vsp-card-subtitle {
  font-size: 12px;
  color: rgba(148, 163, 184, 0.9);
}

.vsp-card-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.vsp-card-body {
  font-size: 13px;
}

/* Filters & inputs */
.vsp-filters-row {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 10px;
}

.vsp-input {
  background: rgba(15, 23, 42, 0.92);
  border-radius: 999px;
  border: 1px solid rgba(148, 163, 184, 0.45);
  padding: 4px 10px;
  font-size: 12px;
  color: #e5e7eb;
}

.vsp-input::placeholder {
  color: rgba(148, 163, 184, 0.7);
}

.vsp-chip-btn {
  border-radius: 999px;
  border: 1px solid rgba(148, 163, 184, 0.45);
  background: radial-gradient(
    circle at top left,
    rgba(56, 189, 248, 0.18),
    rgba(15, 23, 42, 0.96)
  );
  padding: 4px 12px;
  font-size: 11px;
  cursor: pointer;
  color: #e5e7eb;
}

.vsp-chip-btn:hover {
  transform: translateY(-1px);
  box-shadow: 0 12px 26px rgba(15, 23, 42, 0.9);
}

/* Tables */
.vsp-table-wrapper {
  max-height: 420px;
  overflow: auto;
}

.vsp-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.vsp-table thead th {
  text-align: left;
  padding: 6px 8px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.25);
  font-weight: 500;
  color: rgba(203, 213, 225, 0.95);
}

.vsp-table tbody td {
  padding: 6px 8px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.12);
  color: rgba(226, 232, 240, 0.96);
}

/* JSON editor & status */
.vsp-json-editor {
  width: 100%;
  min-height: 260px;
  max-height: 420px;
  padding: 10px 12px;
  border-radius: 14px;
  border: 1px solid rgba(148, 163, 184, 0.45);
  background: rgba(15, 23, 42, 0.98);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
    "Liberation Mono", "Courier New", monospace;
  font-size: 12px;
  color: #e5e7eb;
  resize: vertical;
}

.vsp-status-line {
  margin-top: 6px;
  font-size: 11px;
  color: rgba(148, 163, 184, 0.9);
}

/* DataSource pager */
.vsp-ds-pager {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 8px;
}

.vsp-ds-page-info {
  font-size: 11px;
}

/* Section title */
.vsp-section-title {
  font-size: 12px;
  font-weight: 500;
  color: rgba(226, 232, 240, 0.96);
  margin-bottom: 6px;
}
CSS_EOF

echo "[OK] Appended layout CSS V1 vào $CSS"
