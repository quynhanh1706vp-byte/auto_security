#!/usr/bin/env bash
set -euo pipefail

CSS="static/css/security_resilient.css"
echo "[i] CSS = $CSS"

if [ ! -f "$CSS" ]; then
  echo "[ERR] Không tìm thấy $CSS"
  exit 1
fi

python3 - "$CSS" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
css = path.read_text(encoding="utf-8")

marker = "/* DASHBOARD SEVERITY V3 */"
if marker in css:
    print("[INFO] Đã có block V3, bỏ qua.")
else:
    extra = r"""
/* DASHBOARD SEVERITY V3 – bar chart to kiểu ANY-URL */
.dash-severity-card {
  margin-top: 14px;
  padding: 14px 18px 18px;
  border-radius: 20px;
  background: transparent;
}

/* vùng chart */
.dash-severity-bars {
  position: relative;
  height: 220px;
  margin-top: 4px;
  border-radius: 18px;
  background:
    repeating-linear-gradient(
      to top,
      rgba(148,163,184,0.18) 0px,
      rgba(148,163,184,0.18) 1px,
      transparent 1px,
      transparent 24px
    ),
    radial-gradient(circle at top left,#020617,#020617 45%,#00010a 100%);
  box-shadow: 0 0 0 1px rgba(30,64,175,0.8), 0 18px 40px rgba(0,0,0,0.85);
  padding: 18px 28px 26px;
  display: flex;
  align-items: flex-end;
  justify-content: space-around;
}

/* mỗi cột */
.dash-sev-bar {
  flex: 0 0 52px;
  display: flex;
  flex-direction: column-reverse; /* label xuống dưới */
  align-items: center;
  gap: 8px;
  min-width: 52px;
}

.dash-sev-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: .16em;
  opacity: .82;
}

.dash-sev-bar-inner {
  position: relative;
  width: 32px;
  border-radius: 999px;
  overflow: hidden;
  background: rgba(15,23,42,0.95);
  box-shadow: inset 0 0 0 1px rgba(15,23,42,1);
  /* chiều cao theo count, giới hạn max để ko quá dài */
  height: calc(12px + min(var(--sev-count, 0) * 0.02px, 180px));
}

.dash-sev-bar-inner::before {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  opacity: 0.9;
}

/* màu từng cột */
.dash-sev-bar:nth-child(1) .dash-sev-bar-inner::before {
  background: linear-gradient(to top,#7f1d1d,#fecaca);
}
.dash-sev-bar:nth-child(2) .dash-sev-bar-inner::before {
  background: linear-gradient(to top,#7c2d12,#fed7aa);
}
.dash-sev-bar:nth-child(3) .dash-sev-bar-inner::before {
  background: linear-gradient(to top,#78350f,#fef3c7);
}
.dash-sev-bar:nth-child(4) .dash-sev-bar-inner::before {
  background: linear-gradient(to top,#064e3b,#bbf7d0);
}

.dash-sev-count {
  font-size: 12px;
  font-weight: 500;
  opacity: .95;
}

/* responsive */
@media (max-width: 900px) {
  .dash-severity-bars {
    padding: 14px 16px 22px;
  }
  .dash-sev-bar {
    flex-basis: 44px;
    min-width: 44px;
  }
}
"""
    css = css.rstrip() + "\n\n" + marker + extra + "\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã append block DASHBOARD SEVERITY V3.")
PY
