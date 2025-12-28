#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$ROOT/templates/base.html"

echo "[i] BASE = $BASE"
cp "$BASE" "${BASE}.bak_rulesjs_$(date +%Y%m%d_%H%M%S)"
echo "[OK] Backup base.html."

python3 - "$BASE" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

snippet = "{{ url_for('static', filename='patch_rules_layout.js') }}"

if 'patch_rules_layout.js' not in data:
    if '</body>' in data:
        data = data.replace(
            '</body>',
            f'    <script src="{snippet}"></script>\\n</body>'
        )
        print("[OK] Đã thêm script patch_rules_layout.js vào base.html.")
    else:
        print("[WARN] Không tìm thấy </body> để chèn script.")

path.write_text(data, encoding="utf-8")
PY
