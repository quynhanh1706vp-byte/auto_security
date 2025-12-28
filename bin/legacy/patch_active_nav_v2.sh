#!/usr/bin/env bash
set -euo pipefail

APP="$(cd "$(dirname "$0")/.." && pwd)/app.py"
echo "[i] APP = $APP"
cp "$APP" "${APP}.bak_active_$(date +%Y%m%d_%H%M%S)"
echo "[OK] Backup app.py"

python3 - "$APP" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

def add_active(page, html):
    q_pattern = r'render_template\(\s*([\'"])' + re.escape(html) + r'\1(?P<args>[^)]*)\)'
    def repl(m):
        q = m.group(1)
        args = m.group('args') or ""
        if "active_page" in args:
            return m.group(0)
        if args.strip() == "":
            return f'render_template({q}{html}{q}, active_page="{page}")'
        else:
            # args đã bắt đầu bằng dấu phẩy
            return f'render_template({q}{html}{q}{args}, active_page="{page}")'
    return re.sub(q_pattern, repl, data)

# Dashboard
data = add_active("dashboard", "index.html")
data = add_active("dashboard", "dashboard.html")  # nếu có

# Runs
data = add_active("runs", "runs.html")

# Settings
data = add_active("settings", "settings.html")

# Data Source
data = add_active("data_source", "data_source.html")

# Rule overrides
for html in ("rules.html", "rule_overrides.html"):
    data = add_active("rule_overrides", html)

path.write_text(data, encoding="utf-8")
print("[OK] Đã patch active_page cho các trang.")
PY
