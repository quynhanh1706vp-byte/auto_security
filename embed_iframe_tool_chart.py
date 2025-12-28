#!/usr/bin/env python3
from pathlib import Path
import sys

TPL = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/dashboard.html")

if not TPL.is_file():
    print(f"[ERR] Không tìm thấy template: {TPL}", file=sys.stderr)
    sys.exit(1)

txt = TPL.read_text(encoding="utf-8")

marker = "INLINE_IFRAME_TOOL_CHART_START"
if marker in txt:
    print("[i] dashboard.html đã có iframe tool chart, bỏ qua.")
    sys.exit(0)

low = txt.lower()
needle = "findings by tool"
idx = low.find(needle)
if idx == -1:
    print("[WARN] Không tìm thấy 'Findings by tool' trong dashboard.html", file=sys.stderr)
    sys.exit(1)

# chèn ngay sau dòng chứa 'Findings by tool'
line_end = txt.find("\n", idx)
if line_end == -1:
    line_end = len(txt)

snippet = """
    <!-- INLINE_IFRAME_TOOL_CHART_START -->
    <div style="margin-top: 12px; margin-bottom: 8px;">
      <iframe
        src="http://127.0.0.1:8910"
        style="width:100%;height:420px;border:none;border-radius:12px;overflow:hidden;background:transparent;"
        loading="lazy"
        referrerpolicy="no-referrer"
      ></iframe>
    </div>
    <!-- INLINE_IFRAME_TOOL_CHART_END -->
"""

new_txt = txt[:line_end] + snippet + txt[line_end:]

backup = TPL.with_suffix(TPL.suffix + ".bak_iframe2")
backup.write_text(txt, encoding="utf-8")
TPL.write_text(new_txt, encoding="utf-8")

print(f"[OK] Đã chèn iframe tool chart vào {TPL}")
print(f"[i] Backup: {backup}")
