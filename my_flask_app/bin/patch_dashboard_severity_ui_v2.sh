#!/usr/bin/env bash
set -euo pipefail

HTML="SECURITY_BUNDLE_FULL_5_PAGES.html"

if [ ! -f "$HTML" ]; then
  echo "[ERR] Không tìm thấy file $HTML trong thư mục hiện tại."
  exit 1
fi

python3 - <<'PY' "$HTML"
from pathlib import Path
import sys, re

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

original = text

# 1) Đổi tất cả kiểu "INFO + TRACE" hoặc "INFO+TRACE" → "INFO / TRACE"
text = re.sub(r"INFO\s*\+\s*TRACE", "INFO / TRACE", text)

# 2) Chỉnh các đoạn mô tả gộp Medium / Low / Info / Trace → viết hoa đúng chuẩn
text = re.sub(
    r"Medium\s*/\s*Low\s*/\s*Info\s*/\s*Trace",
    "MEDIUM / LOW / INFO / TRACE",
    text,
)

text = re.sub(
    r"Medium\s*\(\s*Medium\s*/\s*Low\s*/\s*Info\s*/\s*Trace\s*\)",
    "MEDIUM (MEDIUM / LOW / INFO / TRACE)",
    text,
)

text = re.sub(
    r"Medium\s*/\s*Low\s*/\s*Info\s*/\s*Trace",
    "MEDIUM / LOW / INFO / TRACE",
    text,
)

# 3) Chỉnh legend chỗ biểu đồ / mô tả chung:
text = re.sub(
    r"Critical\s*/\s*High\s*/\s*Medium\s*/\s*Low\s*/\s*Info\s*/\s*Trace",
    "CRITICAL / HIGH / MEDIUM / LOW / INFO / TRACE",
    text,
)

# 4) Chỉnh tiêu đề top noisy paths nếu có
text = re.sub(
    r"Top noisy paths\s*\(Medium\s*/\s*Low\s*/\s*Info\s*/\s*Trace\)",
    "Top noisy paths (MEDIUM / LOW / INFO / TRACE)",
    text,
)

# 5) Mô tả dưới card INFO / TRACE
text = text.replace(
    "Informational checks, debug / trace-only rules.",
    "Informational checks (INFO) and trace-only rules (TRACE)."
)

if text == original:
    print("[WARN] Không có thay đổi nào (không thấy chuỗi cần sửa).")
else:
    path.write_text(text, encoding="utf-8")
    print(f"[OK] Đã cập nhật wording severity trong {path}")
PY
