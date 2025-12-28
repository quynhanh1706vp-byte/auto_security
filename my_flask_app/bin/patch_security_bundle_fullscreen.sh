#!/usr/bin/env bash
set -euo pipefail

HTML="SECURITY_BUNDLE_FULL_5_PAGES.html"

if [ ! -f "$HTML" ]; then
  echo "[ERR] Không tìm thấy $HTML ở $(pwd)"
  exit 1
fi

python - <<'PY'
from pathlib import Path

p = Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = p.read_text(encoding="utf-8")

link = '<link rel="stylesheet" href="static/css/security_bundle_fullscreen_override.css">'

if "security_bundle_fullscreen_override.css" in html:
    print("[INFO] Đã có CSS override, không chèn thêm.")
else:
    if "</head>" in html:
        html = html.replace("</head>", f"  {link}\n</head>")
        print("[OK] Đã chèn link CSS override trước </head>.")
    else:
        html = link + "\n" + html
        print("[WARN] Không thấy </head>, chèn link CSS lên đầu file.")
    p.write_text(html, encoding="utf-8")
PY

echo "[DONE] Patch fullscreen xong."
