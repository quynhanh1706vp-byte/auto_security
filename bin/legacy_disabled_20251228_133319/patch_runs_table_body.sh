#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/runs.html"
cp "$TPL" "$TPL.bak_$(date +%Y%m%d_%H%M%S)" || true

python3 - "$TPL" <<'PY'
from pathlib import Path

path = Path("templates/runs.html")
data = path.read_text(encoding="utf-8")

marker = "RUN HISTORY"
idx = data.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy 'RUN HISTORY' trong templates/runs.html")
    raise SystemExit(1)

# tìm <tbody> đầu tiên sau RUN HISTORY
tbody_start = data.find("<tbody", idx)
if tbody_start == -1:
    print("[ERR] Không tìm thấy <tbody> sau RUN HISTORY")
    raise SystemExit(1)

tbody_start_close = data.find(">", tbody_start)
if tbody_start_close == -1:
    print("[ERR] Không tìm thấy dấu '>' của <tbody>")
    raise SystemExit(1)
tbody_start_close += 1  # sau dấu '>'

tbody_end = data.find("</tbody>", tbody_start_close)
if tbody_end == -1:
    print("[ERR] Không tìm thấy </tbody>")
    raise SystemExit(1)
tbody_end_close = tbody_end + len("</tbody>")

new_tbody = """<tbody>
          {% if runs %}
            {% for r in runs %}
            <tr>
              <td>
                <a href="/pm_report/{{ r.run_id }}/html">
                  {{ r.run_id }}
                </a>
              </td>
              <td class="num">{{ r.total }}</td>
              <td class="num">{{ r.critical }}</td>
              <td class="num">{{ r.high }}</td>
              <td class="num">{{ r.medium }}</td>
              <td class="num">{{ r.low }}</td>
              <td>
                <a href="/pm_report/{{ r.run_id }}/html">
                  View report
                </a>
              </td>
            </tr>
            {% endfor %}
          {% else %}
            <tr>
              <td colspan="7">No RUN_* found in out/.</td>
            </tr>
          {% endif %}
        </tbody>"""

data = data[:tbody_start] + new_tbody + data[tbody_end_close:]

path.write_text(data, encoding="utf-8")
print("[OK] Đã patch tbody của RUN HISTORY để dùng biến 'runs'.")
PY
