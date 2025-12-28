#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")

# Regex: xoá mọi tag (<small> hoặc <div> ...) có chứa câu "Critical / High / Medium / Low – các bucket..."
pattern = re.compile(
    r"<(small|div)[^>]*>[^<]*Critical\s*/\s*High\s*/\s*Medium\s*/\s*Low\s*–\s*các bucket[^<]*findings_unified\.json[^<]*</\1>",
    re.DOTALL | re.IGNORECASE,
)

new_html, n = pattern.subn("", html)

if n > 0:
    print(f"[OK] Đã xoá {n} block note dài chứa 'Critical / High / Medium / Low – các bucket...'.")
else:
    print("[WARN] Không tìm thấy block note dài (regex không match).")

path.write_text(new_html, encoding="utf-8")
PY
