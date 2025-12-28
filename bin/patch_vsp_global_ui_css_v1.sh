#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSS_DIR="$ROOT/static/css"
CSS_FILE="$CSS_DIR/vsp_global_2025.css"

mkdir -p "$CSS_DIR"

echo "[INFO] ROOT = $ROOT"
echo "[INFO] Viết CSS tổng vào $CSS_FILE"

cat > "$CSS_FILE" << 'CSS'
/* VSP 2025 – Global UI Theme
 * Áp dụng chung cho 5 tab: Dashboard, Runs & Reports, Data Source, Settings, Rule Overrides
 */

:root {
  --vsp-bg: #020617;
  --vsp-bg-alt: #02091b;
  --vsp-bg-soft: #020b21;
  --vsp-border-subtle: rgba(148, 163, 184, 0.25);
  --vsp-border-strong: rgba(148, 163, 184, 0.45);
  --vsp-text: #e5e7eb;
  --vsp-text-soft: #9ca3af;
  --vsp-text-muted: #6b7280;
  --vsp-accent: #38bdf8;
  --vsp-accent-soft: rgba(56, 189, 248, 0.12);
  --vsp-accent-strong: rgba(56, 189, 248, 0.7);
  --vsp-danger: #fb7185;
  --vsp-danger-soft: rgba(248, 113, 113, 0.12);
  --vsp-success: #4ade80;
  --vsp-success-soft: rgba(74, 222, 128, 0.12);
  --vsp-warning: #facc15;
  --vsp-warning-soft: rgba(250, 204, 21, 0.12);
  --vsp-radius-lg: 18px;
  --vsp-radius-md: 12px;
  --vsp-radius-sm: 8px;
  --vsp-shadow-soft: 0 18px 45px rgba(15, 23, 42, 0.8);
  --vsp-shadow-chip: 0 6px 20px rgba(15, 23, 42, 0.75);
  --vsp-chip-bg: rgba(15, 23, 42, 0.8);
}

body.vsp-body,
#vsp-root {
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Inter", sans-serif;
  background: radial-gradient(circle at top left, #0b1120 0, #020617 45%, #000 100%);
  color: var(--vsp-text);
}

/* Shell chung cho app */
#vsp-root .vsp-shell {
  display: grid;
  grid-template-columns: 260px minmax(0, 1fr);
  min-height: 100vh;
  background: transparent;
}

/* Sidebar */
#vsp-root .vsp-sidebar {
  background: linear-gradient(to bottom, rgba(15, 23, 42, 0.98), rgba(15, 23, 42, 0.96));
  border-right: 1px solid var(--vsp-border-subtle);
  box-shadow: 14px 0 40px rgba(15, 23, 42, 0.95);
}

#vsp-root .vsp-sidebar-header {
  padding: 20px 22px 6px;
}

#vsp-root .vsp-sidebar-title {
  font-size: 1.05rem;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: #e5e7eb;
}

#vsp-root .vsp-sidebar-subtitle {
  font-size: 0.76rem;
  color: var(--vsp-text-muted);
}

/* Tabs */
#vsp-root .vsp-tabs {
  display: flex;
  gap: 4px;
  padding: 6px 8px;
  border-radius: 999px;
  background: rgba(15, 23, 42, 0.95);
  border: 1px solid rgba(31, 41, 55, 0.9);
  box-shadow: var(--vsp-shadow-soft);
}

#vsp-root .vsp-tab-btn {
  flex: 1 1 0;
  border-radius: 999px;
  border: 1px solid transparent;
  padding: 8px 10px;
  font-size: 0.8rem;
  font-weight: 500;
  color: var(--vsp-text-soft);
  background: transparent;
  cursor: pointer;
  transition: all 0.18s ease-out;
  white-space: nowrap;
}

#vsp-root .vsp-tab-btn:hover {
  border-color: rgba(148, 163, 184, 0.45);
  background: rgba(15, 23, 42, 0.7);
}

#vsp-root .vsp-tab-btn.is-active {
  color: #e5e7eb;
  border-color: rgba(56, 189, 248, 0.7);
  background: radial-gradient(circle at top, rgba(56, 189, 248, 0.18), rgba(15, 23, 42, 0.95));
  box-shadow: 0 0 0 1px rgba(56, 189, 248, 0.3), 0 16px 36px rgba(15, 23, 42, 0.95);
}

/* Main content wrapper */
#vsp-root .vsp-main {
  padding: 22px 26px 26px;
}

#vsp-root .vsp-main-header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 16px;
}

#vsp-root .vsp-main-title {
  font-size: 1.4rem;
  font-weight: 600;
  letter-spacing: 0.03em;
}

#vsp-root .vsp-main-subtitle {
  font-size: 0.85rem;
  color: var(--vsp-text-muted);
}

/* Card chung */
#vsp-root .vsp-card {
  border-radius: var(--vsp-radius-lg);
  border: 1px solid var(--vsp-border-subtle);
  background: radial-gradient(circle at top left, rgba(15, 23, 42, 0.86), rgba(15, 23, 42, 0.96));
  box-shadow: var(--vsp-shadow-soft);
  padding: 14px 16px 16px;
}

#vsp-root .vsp-card + .vsp-card {
  margin-top: 10px;
}

/* KPI card */
#vsp-root .vsp-kpi-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
  gap: 10px;
}

#vsp-root .vsp-kpi-card {
  border-radius: var(--vsp-radius-md);
  border: 1px solid rgba(31, 41, 55, 0.95);
  background: radial-gradient(circle at top, rgba(15, 23, 42, 0.9), rgba(2, 6, 23, 0.95));
  box-shadow: var(--vsp-shadow-chip);
  padding: 10px 10px 10px;
  position: relative;
  overflow: hidden;
}

#vsp-root .vsp-kpi-label {
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--vsp-text-muted);
}

#vsp-root .vsp-kpi-value {
  margin-top: 4px;
  font-size: 1.3rem;
  font-weight: 600;
  color: #f9fafb;
}

#vsp-root .vsp-kpi-sub {
  margin-top: 2px;
  font-size: 0.78rem;
  color: var(--vsp-text-soft);
}

/* Severity badge */
#vsp-root .vsp-badge,
#vsp-root [data-vsp-badge] {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  border-radius: 999px;
  padding: 2px 8px;
  font-size: 0.7rem;
  font-weight: 500;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

#vsp-root .vsp-badge-sev-critical,
#vsp-root [data-severity="CRITICAL"] {
  background: var(--vsp-danger-soft);
  color: #fecaca;
  border: 1px solid rgba(248, 113, 113, 0.5);
}

#vsp-root .vsp-badge-sev-high,
#vsp-root [data-severity="HIGH"] {
  background: rgba(248, 181, 77, 0.18);
  color: #fed7aa;
  border: 1px solid rgba(251, 146, 60, 0.55);
}

#vsp-root .vsp-badge-sev-medium,
#vsp-root [data-severity="MEDIUM"] {
  background: rgba(251, 191, 36, 0.12);
  color: #fef3c7;
  border: 1px solid rgba(234, 179, 8, 0.5);
}

#vsp-root .vsp-badge-sev-low,
#vsp-root [data-severity="LOW"] {
  background: rgba(56, 189, 248, 0.12);
  color: #e0f2fe;
  border: 1px solid rgba(56, 189, 248, 0.6);
}

#vsp-root .vsp-badge-sev-info,
#vsp-root [data-severity="INFO"],
#vsp-root [data-severity="TRACE"] {
  background: rgba(129, 140, 248, 0.12);
  color: #e0e7ff;
  border: 1px solid rgba(129, 140, 248, 0.6);
}

/* Table style chung (Runs, Data Source, Rule Overrides) */
#vsp-root .vsp-table-wrap {
  margin-top: 6px;
  border-radius: var(--vsp-radius-md);
  border: 1px solid rgba(31, 41, 55, 0.95);
  background: radial-gradient(circle at top, rgba(15, 23, 42, 0.9), rgba(15, 23, 42, 0.98));
  overflow: hidden;
}

#vsp-root table,
#vsp-root .vsp-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.78rem;
}

#vsp-root thead tr {
  background: rgba(15, 23, 42, 0.98);
}

#vsp-root thead th {
  text-align: left;
  padding: 8px 10px;
  font-weight: 500;
  color: var(--vsp-text-soft);
  border-bottom: 1px solid rgba(31, 41, 55, 0.95);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  font-size: 0.7rem;
}

#vsp-root tbody tr {
  border-bottom: 1px solid rgba(30, 64, 175, 0.5);
}

#vsp-root tbody tr:nth-child(even) {
  background: rgba(15, 23, 42, 0.9);
}

#vsp-root tbody tr:hover {
  background: radial-gradient(circle at left, rgba(56, 189, 248, 0.08), rgba(15, 23, 42, 0.98));
}

#vsp-root td {
  padding: 7px 10px;
  color: var(--vsp-text);
}

/* Filter bar / toolbar */
#vsp-root .vsp-toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}

#vsp-root .vsp-toolbar-left,
#vsp-root .vsp-toolbar-right {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  align-items: center;
}

#vsp-root .vsp-input,
#vsp-root .vsp-select {
  background: rgba(15, 23, 42, 0.9);
  border-radius: 999px;
  border: 1px solid rgba(51, 65, 85, 0.95);
  padding: 6px 10px;
  font-size: 0.78rem;
  color: var(--vsp-text);
  min-width: 160px;
}

#vsp-root .vsp-input::placeholder {
  color: var(--vsp-text-muted);
}

#vsp-root .vsp-btn {
  border-radius: 999px;
  border: 1px solid rgba(56, 189, 248, 0.4);
  padding: 6px 12px;
  font-size: 0.78rem;
  font-weight: 500;
  color: #e0f2fe;
  background: radial-gradient(circle at top, rgba(56, 189, 248, 0.22), rgba(15, 23, 42, 0.96));
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  transition: all 0.16s ease-out;
}

#vsp-root .vsp-btn:hover {
  border-color: rgba(56, 189, 248, 0.9);
  background: radial-gradient(circle at top, rgba(56, 189, 248, 0.32), rgba(15, 23, 42, 0.98));
  box-shadow: 0 10px 25px rgba(8, 47, 73, 0.9);
}

/* Chart zone */
#vsp-root .vsp-chart-card {
  border-radius: var(--vsp-radius-lg);
  border: 1px solid rgba(31, 41, 55, 0.95);
  background: radial-gradient(circle at top left, rgba(15, 23, 42, 0.9), rgba(15, 23, 42, 0.98));
  padding: 10px 12px 12px;
  box-shadow: var(--vsp-shadow-soft);
}

#vsp-root .vsp-chart-title {
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.09em;
  color: var(--vsp-text-soft);
  margin-bottom: 6px;
}

#vsp-root .vsp-chart-sub {
  font-size: 0.72rem;
  color: var(--vsp-text-muted);
  margin-bottom: 6px;
}

/* Settings & Rule Overrides sections */
#vsp-root .vsp-section-title {
  font-size: 0.9rem;
  font-weight: 500;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--vsp-text-soft);
  margin-bottom: 4px;
}

#vsp-root .vsp-section-desc {
  font-size: 0.78rem;
  color: var(--vsp-text-muted);
  max-width: 620px;
}

/* Empty state */
#vsp-root .vsp-empty {
  border-radius: var(--vsp-radius-md);
  border: 1px dashed rgba(55, 65, 81, 0.9);
  background: rgba(15, 23, 42, 0.8);
  padding: 14px 14px;
  margin-top: 10px;
  font-size: 0.8rem;
  color: var(--vsp-text-soft);
}
CSS

# Các template cần thêm link CSS mới
for TPL in "$ROOT/templates/vsp_dashboard_2025.html" "$ROOT/templates/vsp_5tabs_full.html"; do
  if [ ! -f "$TPL" ]; then
    continue
  fi
  BAK="${TPL}.bak_global_css_$(date +%Y%m%d_%H%M%S)"
  cp "$TPL" "$BAK"
  echo "[BACKUP] $TPL -> $BAK"

  python - << PY
from pathlib import Path

path = Path(r"$TPL")
txt = path.read_text(encoding="utf-8")

link_tag = "{{ url_for('static', filename='css/vsp_global_2025.css') }}"

if link_tag in txt:
    print("[INFO] Link CSS đã tồn tại trong", path.name)
else:
    insert = '    <link rel="stylesheet" href="' + link_tag + '">\\n'
    if "</head>" in txt:
        txt = txt.replace("</head>", insert + "</head>")
        print("[PATCH] Đã chèn link vsp_global_2025.css vào", path.name)
    else:
        print("[WARN] Không tìm thấy </head> trong", path.name)

    path.write_text(txt, encoding="utf-8")
PY
done

echo "[DONE] patch_vsp_global_ui_css_v1.sh hoàn tất."
