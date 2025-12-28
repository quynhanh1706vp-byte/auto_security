#!/usr/bin/env bash
set -euo pipefail

HTML="SECURITY_BUNDLE_FULL_5_PAGES.html"

if [ ! -f "$HTML" ]; then
  echo "[ERR] Không tìm thấy $HTML ở $(pwd)"
  exit 1
fi

python - <<'PY'
from pathlib import Path
import re

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
text = p.read_text(encoding="utf-8")

pattern = r"/\* fake chart area \*/[\\s\\S]*?/\\* RESPONSIVE \\*/"

replacement = r"""/* fake chart area */
    .trend-area {
      position: relative;
      flex: 1;
      min-height: 130px;
      border-radius: 14px;
      background: radial-gradient(circle at top left,
                  rgba(34, 197, 94, 0.16), #020617);
      overflow: hidden;
      padding: 8px 10px;
    }

    .trend-grid {
      position: absolute;
      inset: 12px 10px 16px;
      border-radius: 10px;
      background: rgba(15, 23, 42, 0.95);
      box-shadow:
        inset 0 0 0 1px rgba(34, 197, 94, 0.16),
        0 0 24px rgba(15, 23, 42, 0.9);
    }

    .trend-grid::before,
    .trend-grid::after {
      content: "";
      position: absolute;
      left: 10px;
      right: 10px;
      border-top: 1px dashed rgba(148, 163, 184, 0.22);
    }

    .trend-grid::before {
      top: 30%;
    }

    .trend-grid::after {
      top: 60%;
    }

    .trend-line {
      position: absolute;
      inset: 22px 20px 20px;
      border-radius: 999px;
      border-bottom: 2px solid #22c55e;
      box-shadow: 0 0 14px rgba(34, 197, 94, 0.9);
      transform-origin: left center;
      transform: rotate(3deg);
      background: linear-gradient(90deg,
        rgba(34, 197, 94, 0.0),
        rgba(34, 197, 94, 0.35),
        rgba(34, 197, 94, 0.0));
    }

    .trend-x-axis {
      position: absolute;
      left: 18px;
      right: 18px;
      bottom: 10px;
      display: flex;
      justify-content: space-between;
      font-size: 9px;
      color: rgba(148, 163, 184, 0.7);
    }

    .trend-x-axis span {
      white-space: nowrap;
    }

    .bar-wrapper {
      flex: 1;
      min-height: 140px;
      display: flex;
      align-items: flex-end;
      gap: 10px;
      padding: 6px 4px 4px;
    }

    .bar {
      flex: 1;
      border-radius: 8px 8px 0 0;
      background: linear-gradient(180deg, #facc15, #f97316);
      box-shadow: 0 0 16px rgba(250, 204, 21, 0.7);
      height: 120px;
    }

    .bar-muted {
      flex: 1;
      height: 24px;
      border-radius: 8px 8px 0 0;
      background: linear-gradient(180deg,
                  rgba(148, 163, 184, 0.55),
                  rgba(30, 41, 59, 0.9));
      box-shadow: 0 0 8px rgba(148, 163, 184, 0.5);
    }

    .bar-label-row {
      display: flex;
      justify-content: space-between;
      font-size: 10px;
      color: var(--text-muted);
      margin-top: 4px;
    }

    /* RESPONSIVE */
"""

new_text, count = re.subn(pattern, replacement, text)
if count == 0:
    print("[ERR] Không tìm thấy block CSS 'fake chart area' để thay.")
else:
    p.write_text(new_text, encoding="utf-8")
    print(f"[OK] Đã thay {count} block CSS chart.")
PY
