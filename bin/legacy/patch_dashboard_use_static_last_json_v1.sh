#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

JS="static/index_fallback_dashboard.js"

if [[ ! -f "$JS" ]]; then
  echo "[ERR] Không tìm thấy $JS" >&2
  exit 1
fi

python3 - << 'PY'
from pathlib import Path
import re

js = Path("static/index_fallback_dashboard.js")
data = js.read_text(encoding="utf-8")
before = data

# Ép SUMMARY_URL & FINDINGS_URL trỏ về file static last_*.json
data = re.sub(
    r"const\s+SUMMARY_URL\s*=\s*[^;]+;",
    "const SUMMARY_URL = '/static/last_summary_unified.json';",
    data,
    flags=re.MULTILINE,
)
data = re.sub(
    r"const\s+FINDINGS_URL\s*=\s*[^;]+;",
    "const FINDINGS_URL = '/static/last_findings.json';",
    data,
    flags=re.MULTILINE,
)

js.write_text(data, encoding="utf-8")

print("[OK] Đã patch SUMMARY_URL/FINDINGS_URL"
      if data != before else
      "[WARN] Không thấy SUMMARY_URL/FINDINGS_URL để patch – nội dung file có thể khác kỳ vọng.")
PY
