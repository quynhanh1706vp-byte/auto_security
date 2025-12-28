#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$ROOT/templates/base.html"

if [ ! -f "$BASE" ]; then
  echo "[ERR] Không tìm thấy $BASE" >&2
  exit 1
fi

BKP="$BASE.bak_nav_settings_$(date +%Y%m%d_%H%M%S)"
cp "$BASE" "$BKP"
echo "[i] Backup base.html -> $BKP"

python3 - "$BASE" << 'PY'
from pathlib import Path
import re, sys

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")
orig = data

# Regex khá "thoáng" – tìm <div class="nav-item ...> ... Settings ... </div>
pattern = re.compile(
    r'<div\s+class="nav-item[^"]*">.*?Settings.*?</div>',
    re.DOTALL
)

m = pattern.search(data)
if not m:
    print("[WARN] Không tìm thấy block nav-item chứa 'Settings' để patch.")
    sys.exit(0)

print("[INFO] Tìm thấy block nav Settings, sẽ thay thế toàn bộ.")

new_block = '''
<div class="nav-item {% if request.path.startswith('/settings') %}active{% endif %}">
  <a href="/settings">Settings</a>
</div>'''.strip()

data = data[:m.start()] + new_block + data[m.end():]
path.write_text(data, encoding="utf-8")
print("[OK] Đã patch nav Settings trong base.html (dùng request.path để set active).")
PY

echo "[DONE] patch_nav_settings_active_v1.sh hoàn thành."
