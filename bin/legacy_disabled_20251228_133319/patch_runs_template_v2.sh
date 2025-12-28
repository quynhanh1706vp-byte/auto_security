#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/runs.html"
echo "[i] Patch $TPL để render bảng từ biến 'runs'..."

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/runs.html")
data = tpl.read_text(encoding="utf-8")
old = data

pattern = re.compile(r"<tbody>.*?No RUN_\* found in out/.*?</tbody>", re.DOTALL)

replacement = """<tbody>
{% if runs %}
  {% for r in runs %}
  <tr>
    <td class="cell-run-id">
      <a href="/pm_report/{{ r.run_id }}/html">{{ r.run_id }}</a>
    </td>
    <td class="cell-num">{{ r.total }}</td>
    <td class="cell-num">{{ r.C }}</td>
    <td class="cell-num">{{ r.H }}</td>
    <td class="cell-num">{{ r.M }}</td>
    <td class="cell-num">{{ r.L }}</td>
    <td class="cell-link">
      <a href="/pm_report/{{ r.run_id }}/html">HTML report</a>
    </td>
  </tr>
  {% endfor %}
{% else %}
  <tr>
    <td colspan="7">No RUN_* found in out/.</td>
  </tr>
{% endif %}
</tbody>"""

new = pattern.sub(replacement, data)
if new == data:
    print("[WARN] Không tìm được đoạn tbody chứa 'No RUN_* found in out/.' để thay.")
else:
    tpl.write_text(new, encoding="utf-8")
    print("[OK] Đã thay tbody trong runs.html")
PY

echo "[DONE] patch_runs_template_v2.sh hoàn thành."
