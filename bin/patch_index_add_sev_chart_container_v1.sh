#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

python3 - << 'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")

marker = "SEVERITY BUCKETS"
idx = data.find(marker)
if idx == -1:
    print("[WARN] Không tìm thấy 'SEVERITY BUCKETS' trong templates/index.html – không patch được.")
else:
    # Tìm thẻ </div> sau chữ 'SEVERITY BUCKETS' (tiêu đề card)
    close = data.find("</", idx)
    if close == -1:
        print("[WARN] Không tìm thấy thẻ kết thúc sau 'SEVERITY BUCKETS' – không patch được.")
    else:
        close = data.find(">", close)
        if close == -1:
            print("[WARN] Không tìm được '>' của thẻ kết thúc – không patch được.")
        else:
            insert_pos = close + 1
            snippet = '\n          <div id="sb-sev-chart-v2" class="sbv3-severity-chart"></div>\n'
            new_data = data[:insert_pos] + snippet + data[insert_pos:]
            path.write_text(new_data, encoding="utf-8")
            print("[OK] Đã chèn container #sb-sev-chart-v2 vào dưới tiêu đề SEVERITY BUCKETS.")
PY
