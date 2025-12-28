#!/usr/bin/env bash
set -euo pipefail

CSS="/home/test/Data/SECURITY_BUNDLE/ui/static/css/security_resilient.css"
echo "[i] CSS = $CSS"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy security_resilient.css"
  exit 1
fi

python3 - "$CSS" <<'PY'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    css = f.read()

marker = "/* DASHBOARD PRETTY V1 */"

if marker in css:
    print("[INFO] CSS Dashboard pretty đã tồn tại, bỏ qua.")
else:
    extra = """
/* DASHBOARD PRETTY V1 */
.dash-section {
  margin-bottom: 32px;
}

.dash-metrics-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 20px;
  margin-bottom: 24px;
}

.dash-metric-card {
  flex: 1 1 220px;
  min-width: 220px;
  max-width: 320px;
  background: rgba(255, 255, 255, 0.02);
  border-radius: 16px;
  padding: 14px 18px;
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.02);
}

.dash-metric-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: .12em;
  opacity: .7;
  margin-bottom: 6px;
}

.dash-metric-value {
  font-size: 26px;
  font-weight: 600;
  margin-bottom: 4px;
}

.dash-metric-sub {
  font-size: 12px;
  opacity: .8;
  line-height: 1.4;
}

.dash-severity-card {
  margin-top: 8px;
  padding: 14px 18px 10px;
  border-radius: 16px;
  background: radial-gradient(circle at top, rgba(255,255,255,0.06), rgba(0,0,0,0.8));
}

.dash-severity-bars {
  display: flex;
  gap: 18px;
}

.dash-sev-bar {
  flex: 1 1 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
}

.dash-sev-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: .12em;
  opacity: .7;
}

.dash-sev-label.crit { color: #ff6b81; }
.dash-sev-label.high { color: #ffb347; }
.dash-sev-label.med  { color: #ffd75e; }
.dash-sev-label.low  { color: #4cd964; }

.dash-sev-bar-inner {
  width: 12px;
  border-radius: 999px;
  background: linear-gradient(to top, #ff6b81, #ffd75e);
  height: calc(12px + (var(--sev-count, 0) * 0.6px));
  min-height: 14px;
}

.dash-sev-count {
  font-size: 12px;
  opacity: .85;
}

.dash-bottom-grid {
  display: grid;
  grid-template-columns: minmax(0, 2.2fr) minmax(0, 1.5fr);
  gap: 24px;
}

@media (max-width: 1100px) {
  .dash-bottom-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}

.dash-bottom-card {
  background: rgba(255, 255, 255, 0.02);
  border-radius: 18px;
  padding: 16px 18px 12px;
}

.dash-bottom-card h3 {
  margin-bottom: 10px;
}

.dash-table-wrapper {
  max-height: 260px;
  overflow: auto;
}

.dash-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.dash-table th,
.dash-table td {
  padding: 5px 6px;
  border-bottom: 1px solid rgba(255,255,255,0.04);
}

.dash-table th {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: .12em;
  opacity: .75;
  text-align: left;
}

.dash-table td.right {
  text-align: right;
}

.dash-table td.small {
  font-size: 11px;
}

.dash-table td.mono {
  font-family: "Fira Code", "SF Mono", monospace;
}

.dash-empty-hint {
  font-size: 12px;
  opacity: .8;
}

.sev-pill {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
}

.sev-pill.high {
  background: rgba(255, 179, 71, 0.18);
  color: #ffb347;
}

.sev-pill.critical {
  background: rgba(255, 107, 129, 0.18);
  color: #ff6b81;
}
"""
    css = css.rstrip() + "\n\n" + extra + "\n"

    with open(path, "w", encoding="utf-8") as f:
        f.write(css)
    print("[OK] Đã append CSS Dashboard pretty.")
PY
