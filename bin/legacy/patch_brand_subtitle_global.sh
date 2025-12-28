#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL_DIR="$ROOT/templates"

echo "[i] TEMPLATES DIR = $TPL_DIR"

# Backup gộp: zip nhanh toàn bộ templates trước khi sửa
BACKUP="$ROOT/templates_backup_brand_$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czf "$BACKUP" -C "$ROOT" templates
echo "[OK] Đã backup toàn bộ templates -> $BACKUP"

python3 - <<'PY'
import pathlib, sys

root = pathlib.Path("templates")
count_files = 0
count_hits = 0

for path in root.rglob("*.html"):
    text = path.read_text(encoding="utf-8")
    if "Scan Dashboard" in text:
        count_files += 1
        count_hits += text.count("Scan Dashboard")
        text = text.replace("Scan Dashboard", "Dashboard & Reports")
        path.write_text(text, encoding="utf-8")
        print(f"[OK] Patched: {path}")

print(f"[INFO] Files patched: {count_files}, occurrences replaced: {count_hits}")
PY
