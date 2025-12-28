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
css  = path.read_text(encoding="utf-8")

marker = "/* DASHBOARD SEVERITY V2 */"
if marker in css:
    print("[INFO] Đã có block DASHBOARD SEVERITY V2, bỏ qua.")
else:
    extra = r"""
/* DASHBOARD SEVERITY V2 – làm đẹp lại 4 cột CRIT/HIGH/MED/LOW */
.dash-severity-card {
  margin-top: 8px;
  padding: 18px 22px 14px;
  border-radius: 20px;
  background: radial-gradient(circle at top left, #020617, #020617 45%, #00010a 100%);
  box-shadow: 0 0 0 1px rgba(15,23,42,0.8), 0 20px 40px rgba(0,0,0,0.75);
}

.dash-severity-bars {
  display: flex;
  justify-content: space-evenly;
  align-items: flex-end;
  gap: 26px;
}

.dash-sev-bar {
  flex: 0 0 auto;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  min-width: 56px;
}

.dash-sev-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: .14em;
  opacity: .78;
}

.dash-sev-bar-inner {
  position: relative;
  width: 10px;
  border-radius: 999px;
  overflow: hidden;
  background: rgba(15,23,42,0.9);
  box-shadow: inset 0 0 0 1px rgba(30,64,175,0.7);
  /* chiều cao dựa trên var(--sev-count), nhưng limit để không quá to */
  height: calc(26px + min(var(--sev-count, 0) * 0.8px, 80px));
}

.dash-sev-bar-inner::before {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  background: linear-gradient(to top, rgba(15,23,42,0.2), rgba(248,250,252,0.15));
}

.dash-sev-bar-inner::after {
  content: "";
  position: absolute;
  top: 5px;
  left: 50%;
  transform: translateX(-50%);
  width: 14px;
  height: 14px;
  border-radius: 999px;
  box-shadow: 0 0 0 1px rgba(15,23,42,0.9), 0 0 10px rgba(148,163,184,0.7);
}

/* màu cho từng cột – dùng nth-child để khỏi sửa HTML */
.dash-sev-bar:nth-child(1) .dash-sev-bar-inner::after {
  background: #f97373;
}
.dash-sev-bar:nth-child(1) .dash-sev-bar-inner::before {
  background: linear-gradient(to top, #7f1d1d, #fecaca);
}

.dash-sev-bar:nth-child(2) .dash-sev-bar-inner::after {
  background: #fb923c;
}
.dash-sev-bar:nth-child(2) .dash-sev-bar-inner::before {
  background: linear-gradient(to top, #7c2d12, #fed7aa);
}

.dash-sev-bar:nth-child(3) .dash-sev-bar-inner::after {
  background: #facc15;
}
.dash-sev-bar:nth-child(3) .dash-sev-bar-inner::before {
  background: linear-gradient(to top, #78350f, #fef3c7);
}

.dash-sev-bar:nth-child(4) .dash-sev-bar-inner::after {
  background: #22c55e;
}
.dash-sev-bar:nth-child(4) .dash-sev-bar-inner::before {
  background: linear-gradient(to top, #064e3b, #bbf7d0);
}

.dash-sev-count {
  font-size: 12px;
  opacity: .9;
}
@media (max-width: 900px) {
  .dash-severity-bars {
    gap: 18px;
  }
  .dash-sev-bar {
    min-width: 48px;
  }
}
"""
    css = css.rstrip() + "\n\n" + marker + extra + "\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã append block DASHBOARD SEVERITY V2.")
PY
