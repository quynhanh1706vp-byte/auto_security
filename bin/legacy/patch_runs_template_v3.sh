#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/runs.html"
echo "[i] TPL = $TPL"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/runs.html")
text = tpl.read_text(encoding="utf-8")

pattern = re.compile(r"<tbody[^>]*>.*?</tbody>", re.DOTALL)

new_tbody = """
          <tbody>
          {% if runs %}
            {% for r in runs %}
            <tr>
              <td>{{ r.id }}</td>
              <td>—</td>
              <td>{{ r.src }}</td>
              <td style="text-align:right">{{ r.total }}</td>
              <td style="text-align:right">{{ r.crit }}/{{ r.high }}</td>
              <td>{{ r.mode }}</td>
              <td>
                <a href="/pm_report/{{ r.id }}/html">HTML</a>
                <a href="/pm_report/{{ r.id }}/pdf">PDF</a>
              </td>
            </tr>
            {% endfor %}
          {% else %}
            <tr>
              <td colspan="7" style="text-align:center;opacity:.7">
                Chưa có RUN nào trong out/.
              </td>
            </tr>
          {% endif %}
          </tbody>
"""

if not pattern.search(text):
    raise SystemExit("[ERR] Không tìm thấy <tbody> trong templates/runs.html")

tpl.write_text(pattern.sub(new_tbody, text), encoding="utf-8")
print("[OK] Đã thay tbody trong templates/runs.html thành bản động.")
PY
