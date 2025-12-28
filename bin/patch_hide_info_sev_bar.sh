#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/index.html"
cp "$TPL" "$TPL.bak_hide_info_$(date +%Y%m%d_%H%M%S)" || true

python3 - <<'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")

snippet = "    .sev-chart .sev-bar:last-child { display: none; }\n"

if ".sev-chart .sev-bar:last-child" in data:
    print("[INFO] CSS hide Info bar đã tồn tại, bỏ qua.")
else:
    marker = "/* SEVERITY BAR CHART */"
    if marker in data:
        data = data.replace(marker, marker + "\n" + snippet, 1)
    else:
        # fallback: chèn trước </style>
        end = "</style>"
        if end in data:
            data = data.replace(end, snippet + end, 1)
        else:
            data += "\n<style>\n" + snippet + "</style>\n"

    path.write_text(data, encoding="utf-8")
    print("[OK] Đã chèn CSS ẩn cột Info trong biểu đồ.")
PY
