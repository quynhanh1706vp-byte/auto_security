#!/usr/bin/env bash
set -euo pipefail
APP="$(cd "$(dirname "$0")/.." && pwd)/app.py"
echo "[i] APP = $APP"
cp "$APP" "${APP}.bak_$(date +%Y%m%d_%H%M%S)"

python3 - "$APP" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

mapping = {
    "index.html": "dashboard",
    "runs.html": "runs",
    "settings.html": "settings",
    "data_source.html": "data_source",
    "rules.html": "rule_overrides",
    "rule_overrides.html": "rule_overrides",
}
for tpl, page in mapping.items():
    for quote in ('"', "'"):
        old = f"render_template({quote}{tpl}{quote}"
        new = f'render_template({quote}{tpl}{quote}, active_page="{page}"'
        if old in data and f'active_page="{page}"' not in data:
            data = data.replace(old, new)

path.write_text(data, encoding="utf-8")
print("[OK] Đã thêm active_page cho các trang.")
PY
