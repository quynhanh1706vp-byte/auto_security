#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

python3 - <<'PY'
from pathlib import Path
import re

path = Path("templates/runs.html")
data = path.read_text(encoding="utf-8")

pattern = re.compile(r"<tbody>.*?No RUN_\* found in out/.*?</tbody>", re.S)
new_tbody = """<tbody>
          {% if runs %}
            {% for r in runs %}
            <tr>
              <td>{{ r.run_id }}</td>
              <td class="num">{{ r.total }}</td>
              <td class="num">{{ r.c }}</td>
              <td class="num">{{ r.h }}</td>
              <td class="num">{{ r.m }}</td>
              <td class="num">{{ r.l }}</td>
              <td>
                {% if r.report_html %}
                  <a href="{{ r.report_html }}" target="_blank">HTML</a>
                {% else %}
                  -
                {% endif %}
              </td>
            </tr>
            {% endfor %}
          {% else %}
            <tr>
              <td colspan="7">No RUN_* found in out/.</td>
            </tr>
          {% endif %}
          </tbody>"""

new_data, n = pattern.subn(new_tbody, data)
if n == 0:
    print("[WARN] Không tìm thấy <tbody> placeholder trong runs.html")
else:
    path.write_text(new_data, encoding="utf-8")
    print(f"[OK] Đã patch runs.html (tbody, {n} block).")
PY
