#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$ROOT/templates/base.html"
TPL="$ROOT/templates/settings.html"

if [ ! -f "$BASE" ]; then
  echo "[ERR] Không tìm thấy $BASE" >&2
  exit 1
fi
if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

BKP="$TPL.bak_blockfix_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BKP"
echo "[i] Backup settings.html -> $BKP"

python3 - << 'PY'
from pathlib import Path
import re

root = Path("templates")
base = (root / "base.html").read_text(encoding="utf-8")

# Tìm tất cả block trong base.html
blocks = re.findall(r'{%\s*block\s+(\w+)\s*%}', base)
seen = set()
order = []
for b in blocks:
    if b not in seen:
        seen.add(b)
        order.append(b)

preferred = ["content", "body", "main", "page", "page_content"]
block_name = None

for name in preferred:
    if name in order:
        block_name = name
        break

if block_name is None:
    # Lấy block đầu tiên không phải mấy block meta
    skip = {"title", "head", "extra_css", "extra_js", "scripts"}
    for name in order:
        if name not in skip:
            block_name = name
            break

if block_name is None:
    block_name = "content"

print(f"[INFO] Sẽ override block: {block_name!r}")

tpl = root / "settings.html"

html = f'''{{% extends "base.html" %}}

{{% block title %}}SECURITY BUNDLE – Settings{{% endblock %}}

{{% block {block_name} %}}
<div class="sb-main">
  <div class="sb-main-header">
    <div class="sb-main-title">Settings</div>
  </div>

  <div class="sb-main-body">
    <section class="sb-section sb-section-full">
      <div class="sb-section-header">
        <div class="sb-section-title">By tool / config</div>
      </div>

      <div class="sb-card sb-card-fill">
        <div class="sb-card-body">
          <div class="sb-help-line">
            <span class="sb-help-label">Config file:</span>
            <code class="sb-pill-strong">{{{{ cfg_path }}}}</code>
          </div>

          <div class="sb-table-wrapper sb-table-wrapper-settings">
            <table class="sb-table sb-table-settings">
              <thead>
                <tr>
                  <th>Tool</th>
                  <th>Enabled</th>
                  <th>Level</th>
                  <th>Modes</th>
                  <th>Notes</th>
                </tr>
              </thead>
              <tbody>
                {{% for row in rows %}}
                <tr>
                  <td class="sb-col-tool">{{{{ row.tool }}}}</td>
                  <td class="sb-col-enabled">
                    {{% if row.enabled %}}
                      <span class="sb-tag sb-tag-on">true</span>
                    {{% else %}}
                      <span class="sb-tag sb-tag-off">false</span>
                    {{% endif %}}
                  </td>
                  <td class="sb-col-level">
                    <span class="sb-level-pill sb-level-{{{{ row.level|default('std')|lower }}}}">
                      {{{{ row.level|upper }}}}
                    </span>
                  </td>
                  <td class="sb-col-modes">{{{{ row.modes }}}}</td>
                  <td class="sb-col-notes">{{{{ row.notes }}}}</td>
                </tr>
                {{% endfor %}}
              </tbody>
            </table>
          </div>

        </div>
      </div>
    </section>
  </div>
</div>
{{% endblock %}}
'''

tpl.write_text(html, encoding="utf-8")
print("[OK] Đã ghi lại templates/settings.html với block tên:", block_name)
PY
