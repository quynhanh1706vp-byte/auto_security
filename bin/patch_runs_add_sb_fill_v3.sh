#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/runs.html"

echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
data = open(path, encoding="utf-8").read()

marker = '</script>\n\n</body>'
snippet = '''</script>
<script src="{{ url_for('static', filename='sb_fill_runs_table_v3.js') }}"></script>

</body>'''

if "sb_fill_runs_table_v3.js" in data:
    print("[INFO] runs.html đã có sb_fill_runs_table_v3.js, không chèn nữa.")
else:
    if marker not in data:
        print("[WARN] Không tìm thấy marker để chèn script, bạn cần chèn tay.")
    else:
        data = data.replace(marker, snippet)
        open(path, "w", encoding="utf-8").write(data)
        print("[OK] Đã chèn sb_fill_runs_table_v3.js vào runs.html")
PY

echo "[DONE] patch_runs_add_sb_fill_v3.sh hoàn thành."
