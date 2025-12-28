#!/usr/bin/env bash
ROOT="/home/test/Data/SECURITY_BUNDLE/ui/my_flask_app/my_flask_app"
TPL="$ROOT/templates/index.html"

python3 - <<'PY'
from pathlib import Path

root = Path("/home/test/Data/SECURITY_BUNDLE/ui/my_flask_app/my_flask_app")
tpl = root / "templates" / "index.html"

data = tpl.read_text(encoding="utf-8")

needle = "security_bundle.css') }}">"
insert = needle + '\\n    <link rel="stylesheet" href="{{ url_for(\\'static\\', filename=\\'css/dashboard_fix_responsive.css\\') }}">'

if needle in data:
    data = data.replace(needle, insert)
    tpl.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn dashboard_fix_responsive.css vào index.html")
else:
    print("[WARN] Không tìm thấy dòng security_bundle.css trong index.html; cần chèn tay.")
PY
