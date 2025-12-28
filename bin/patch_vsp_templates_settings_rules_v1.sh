#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

echo "[PATCH] Patching templates for Settings + Rule Overrides JS & panels..."

python - << 'PY'
from pathlib import Path
import re

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
templates = [
    root / "templates" / "vsp_dashboard_2025.html",
    root / "templates" / "index.html",
    root / "templates" / "vsp_index.html",
]

for tpl in templates:
    if not tpl.is_file():
        continue

    print(f"[PATCH] Checking {tpl}")
    txt = tpl.read_text(encoding="utf-8")
    orig = txt
    changed = False

    # 1) Thêm script JS nếu chưa có
    if "vsp_settings_v1.js" not in txt:
        script_block = (
            '\n    <script src="/static/js/vsp_settings_v1.js"></script>\n'
            '    <script src="/static/js/vsp_rule_overrides_v1.js"></script>\n'
        )
        # chèn trước </body>
        new_txt, n = re.subn(
            r"</body>",
            script_block + "</body>",
            txt,
            count=1,
            flags=re.IGNORECASE,
        )
        if n == 0:
            print(f"[WARN] Không tìm thấy </body> trong {tpl}, bỏ qua chèn script.")
        else:
            txt = new_txt
            changed = True
            print(f"[PATCH]   + Injected script tags vào {tpl}")

    # 2) Thêm container vsp-settings-panel nếu chưa có
    if "vsp-settings-panel" not in txt:
        m = re.search(r'id=["\']tab-settings["\'][^>]*>', txt)
        if m:
            insert_at = m.end()
            inject = '\n  <div id="vsp-settings-panel"></div>'
            txt = txt[:insert_at] + inject + txt[insert_at:]
            changed = True
            print(f"[PATCH]   + Injected <div id='vsp-settings-panel'> vào {tpl}")
        else:
            print(f"[WARN] Không tìm thấy id=\"tab-settings\" trong {tpl}")

    # 3) Thêm container vsp-rule-overrides-panel nếu chưa có
    if "vsp-rule-overrides-panel" not in txt:
        # chấp nhận id="tab-rule-overrides" hoặc "tab-ruleoverrides"
        m = re.search(r'id=["\']tab-rule-?overrides["\'][^>]*>', txt)
        if m:
            insert_at = m.end()
            inject = '\n  <div id="vsp-rule-overrides-panel"></div>'
            txt = txt[:insert_at] + inject + txt[insert_at:]
            changed = True
            print(f"[PATCH]   + Injected <div id='vsp-rule-overrides-panel'> vào {tpl}")
        else:
            print(f"[WARN] Không tìm thấy id=\"tab-rule-overrides\" trong {tpl}")

    if changed and txt != orig:
        backup = tpl.with_suffix(tpl.suffix + ".bak_settings_rules")
        if not backup.is_file():
            backup.write_text(orig, encoding="utf-8")
            print(f"[PATCH]   -> Backup: {backup}")
        tpl.write_text(txt, encoding="utf-8")
        print(f"[PATCH]   -> Updated {tpl}")
    else:
        print(f"[PATCH]   = Không thay đổi {tpl}")

PY

echo "[PATCH] Done."
