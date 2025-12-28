#!/usr/bin/env bash
set -euo pipefail

CSS="static/css/security_resilient.css"

python3 - "$CSS" <<'PY'
from pathlib import Path
path = Path("static/css/security_resilient.css")
css = path.read_text(encoding="utf-8")

marker = "/* [debug_banner_sb_v1] */"
if marker in css:
    print("[i] debug_banner_sb_v1 đã tồn tại.")
else:
    extra = """
/* [debug_banner_sb_v1] – banner debug để kiểm tra đúng CSS chưa */
body::after {
  content: "SB DEBUG THEME ACTIVE";
  position: fixed;
  bottom: 8px;
  right: 12px;
  padding: 4px 8px;
  font-size: 11px;
  background: rgba(255,0,0,0.8);
  color: #fff;
  z-index: 9999;
  border-radius: 4px;
}
"""
    css = css.rstrip() + extra + "\\n"
    path.write_text(css, encoding="utf-8")
    print("[OK] Đã thêm debug_banner_sb_v1 vào", path)
PY

echo "[DONE] patch_debug_banner_css.sh"
