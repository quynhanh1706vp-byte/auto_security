#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$ROOT/templates/base.html"

echo "[i] BASE = $BASE"
cp "$BASE" "${BASE}.bak_navurl_$(date +%Y%m%d_%H%M%S)"

python3 - "$BASE" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

snippet = "{{ url_for('static', filename='patch_sidebar_active_by_url.js') }}"
if 'patch_sidebar_active_by_url.js' not in data:
    if '</body>' in data:
        data = data.replace('</body>', f'    <script src="{snippet}"></script>\\n</body>')
        print("[OK] Added patch_sidebar_active_by_url.js")
    else:
        print("[WARN] </body> not found in base.html")

path.write_text(data, encoding="utf-8")
PY
