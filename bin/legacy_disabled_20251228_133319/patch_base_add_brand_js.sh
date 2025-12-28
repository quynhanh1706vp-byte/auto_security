#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$ROOT/templates/base.html"

echo "[i] BASE = $BASE"

cp "$BASE" "${BASE}.bak_brandjs_$(date +%Y%m%d_%H%M%S)"
echo "[OK] Backup base.html."

python3 - "$BASE" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

snippet = '{{ url_for(\'static\', filename=\'patch_brand_colors.js\') }}'

if 'patch_brand_colors.js' not in data:
    # chèn trước thẻ </body> (hoặc trước block scripts nếu có)
    insert = f'    <script src="{snippet}"></script>\\n</body>'
    if '</body>' in data:
        data = data.replace('</body>', insert)
        print("[OK] Đã thêm script patch_brand_colors.js vào base.html.")
    else:
        print("[WARN] Không tìm thấy </body> trong base.html, không chèn được.")

path.write_text(data, encoding="utf-8")
PY
