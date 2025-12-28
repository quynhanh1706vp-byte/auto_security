#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"
APP="app.py"

python3 - "$APP" << 'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã có root_redirect_to_v2 thì thôi
if "def root_redirect_to_v2(" in data:
    print("[i] root_redirect_to_v2 đã tồn tại, bỏ qua.")
    sys.exit(0)

snippet = textwrap.dedent("""
@app.route("/")
def root_redirect_to_v2():
    \"\"\"Redirect root / sang UI 5 tab (/v2).\"\"\"
    from flask import redirect
    return redirect("/v2")
""")

path.write_text(data.rstrip() + "\n\n" + snippet + "\n", encoding="utf-8")
print("[OK] Đã thêm route / (redirect -> /v2)")
PY
