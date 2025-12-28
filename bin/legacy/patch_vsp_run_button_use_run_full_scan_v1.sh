#!/usr/bin/env bash
set -euo pipefail

TPL="/home/test/Data/SECURITY_BUNDLE/ui/templates/vsp_dashboard_2025.html"

if [[ ! -f "$TPL" ]]; then
  echo "[WARN] Không tìm thấy $TPL, bỏ qua."
  exit 0
fi

BAK="${TPL}.bak_runbtn_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$BAK"
echo "[PATCH] Backup: $BAK"

python - << 'PY'
from pathlib import Path
p = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/vsp_dashboard_2025.html")
txt = p.read_text(encoding="utf-8")
orig = txt
changed = False

# 1) Đổi URL /api/vsp/run_full_ext -> /api/vsp/run_full_scan
if "/api/vsp/run_full_ext" in txt:
    txt = txt.replace("/api/vsp/run_full_ext", "/api/vsp/run_full_scan")
    changed = True
    print("[PATCH] Đã đổi URL run_full_ext -> run_full_scan")

# 2) Đổi payload JSON.stringify({ src_path: src }) -> profile/source_root
old_payload = "JSON.stringify({ src_path: src })"
new_payload = 'JSON.stringify({ profile: "FULL_EXT", source_root: src })'
if old_payload in txt:
    txt = txt.replace(old_payload, new_payload)
    changed = True
    print("[PATCH] Đã đổi payload src_path -> profile/source_root")

if changed and txt != orig:
    p.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã ghi lại template vsp_dashboard_2025.html")
else:
    print("[PATCH] Không có thay đổi.")
PY

echo "[PATCH] Done."
