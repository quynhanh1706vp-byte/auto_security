#!/usr/bin/env bash
set -euo pipefail

HTML="SECURITY_BUNDLE_FULL_5_PAGES.html"

if [ ! -f "$HTML" ]; then
  echo "[ERR] Không tìm thấy file $HTML trong thư mục hiện tại."
  pwd
  ls
  exit 1
fi

python3 - "$HTML" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

needle = "</head>"

# Nếu đã chèn trước đó thì bỏ qua
if "/* FIT SMALL VIEWPORT HEIGHT */" in text:
    print("[INFO] CSS fit viewport đã tồn tại, bỏ qua.")
    sys.exit(0)

inject = """
  <style>
    /* FIT SMALL VIEWPORT HEIGHT */
    @media (max-height: 900px) {
      body {
        zoom: 0.90;
      }
    }
    @media (max-height: 800px) {
      body {
        zoom: 0.80;
      }
    }
  </style>
</head>
"""

if needle not in text:
    print("[ERR] Không tìm thấy </head> để chèn CSS.")
    sys.exit(1)

text = text.replace(needle, inject)
path.write_text(text, encoding="utf-8")
print("[OK] Đã chèn CSS fit viewport vào", path)
PY
