#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSS_FILE="$ROOT/static/css/vsp_ui_layout.css"

if [ ! -f "$CSS_FILE" ]; then
  echo "[ERR] Không tìm thấy $CSS_FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${CSS_FILE}.bak_runs_${TS}"

cp "$CSS_FILE" "$BACKUP"
echo "[BACKUP] $CSS_FILE -> $BACKUP"

cat >> "$CSS_FILE" << 'CSS_EOF'

/* === VSP Runs & Reports – minimal commercial styling v1 === */

#vsp-runs-tbody tr {
  cursor: pointer;
  transition: background 0.12s ease, transform 0.08s ease;
}

#vsp-runs-tbody tr:hover {
  background: rgba(255, 255, 255, 0.03);
}

#vsp-runs-tbody tr.vsp-run-selected {
  background: linear-gradient(
    90deg,
    rgba(56, 189, 248, 0.22),
    rgba(16, 185, 129, 0.22)
  );
}

#vsp-runs-tbody td {
  padding: 6px 10px;
  border-bottom: 1px solid rgba(148, 163, 184, 0.12);
  font-size: 13px;
}

/* Detail panel */
#vsp-run-detail {
  margin-top: 8px;
}

#vsp-run-detail .vsp-run-detail-box {
  background: var(--vsp-surface-soft);
  border-radius: 18px;
  border: 1px solid var(--vsp-border-subtle);
  padding: 14px 16px;
  box-shadow: 0 18px 40px rgba(15, 23, 42, 0.75);
  font-size: 13px;
}

#vsp-run-detail .vsp-run-detail-box strong {
  font-weight: 600;
  color: rgba(226, 232, 240, 0.98);
}

#vsp-run-detail .vsp-run-detail-box div {
  margin-bottom: 4px;
  color: rgba(203, 213, 225, 0.9);
}

/* Export buttons (nếu anh gán class vào nút) */
.vsp-run-export-btn {
  border-radius: 999px;
  border: 1px solid rgba(148, 163, 184, 0.45);
  background: radial-gradient(
    circle at top left,
    rgba(56, 189, 248, 0.22),
    rgba(15, 23, 42, 0.96)
  );
  padding: 6px 12px;
  font-size: 12px;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  color: #e5e7eb;
}

.vsp-run-export-btn:hover {
  transform: translateY(-1px);
  box-shadow: 0 12px 30px rgba(15, 23, 42, 0.9);
}
CSS_EOF

echo "[OK] Đã append CSS cho Runs tab."
