#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$ROOT/templates/base.html"
TPL="$ROOT/templates/settings.html"
CSS="$ROOT/static/css/security_resilient.css"

# ---------- 1) Ghi lại settings.html (không còn dòng Config file:) ----------
if [ ! -f "$BASE" ]; then
  echo "[ERR] Không tìm thấy $BASE" >&2
  exit 1
fi
if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

BKP_TPL="$TPL.bak_hidecfg_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BKP_TPL"
echo "[i] Backup settings.html -> $BKP_TPL"

python3 - << 'PY'
from pathlib import Path
import re

root = Path("templates")
base = (root / "base.html").read_text(encoding="utf-8")

# Tìm tên block nội dung trong base.html
blocks = re.findall(r'{%\s*block\s+(\w+)\s*%}', base)
seen, order = set(), []
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
    skip = {"title", "head", "extra_css", "extra_js", "scripts"}
    for name in order:
        if name not in skip:
            block_name = name
            break

if block_name is None:
    block_name = "content"

print(f"[INFO] Sử dụng block: {block_name!r}")

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
print("[OK] settings.html đã được ghi lại (không còn dòng 'Config file: ...').")
PY

# ---------- 2) CSS: ép màu xanh cho mục Settings trong NAV ----------
if [ ! -f "$CSS" ]; then
  echo "[WARN] Không tìm thấy $CSS để patch màu NAV" >&2
  exit 0
fi

BKP_CSS="$CSS.bak_settingsnav_$(date +%Y%m%d_%H%M%S)"
cp "$CSS" "$BKP_CSS"
echo "[i] Backup security_resilient.css -> $BKP_CSS"

cat >> "$CSS" << 'CSS'


/* FORCE: mục Settings dùng màu xanh giống các nav item khác */
.sidebar .nav-item a[href="/settings"] {
  color: #b7f9b7 !important;       /* chữ xanh lá nhạt */
  background: transparent !important;
}

/* Khi Settings đang được chọn (active) -> giống Dashboard */
.sidebar .nav-item a[href="/settings"].active,
.sidebar .nav-item.active a[href="/settings"] {
  background: #80d36b !important;
  border-color: #c5ff9c !important;
  color: #04130a !important;
}
CSS

echo "[OK] Đã append rule CSS cho mục Settings (màu xanh, không tím)."
