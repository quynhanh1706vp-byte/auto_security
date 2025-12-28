#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/my_flask_app/templates/vsp_5tabs_full.html"

echo "[PATCH] Fix duplicate id vsp-profile + wire profile select"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python - << 'PY'
from pathlib import Path

path = Path("/home/test/Data/SECURITY_BUNDLE/ui/my_flask_app/templates/vsp_5tabs_full.html")
txt = path.read_text(encoding="utf-8")
orig = txt

marker_tab2 = "TAB 2 – Runs &amp; Reports"
idx = txt.find(marker_tab2)
if idx == -1:
    print("[ERR] Không tìm thấy marker TAB 2 – Runs & Reports")
    quit(1)

before = txt[:idx]
after  = txt[idx:]

changed = False

# 1) Trong phần TAB 1 (before): đổi select profile thành id vsp-profile-select
if 'id="vsp-profile"' in before:
    before_new = before.replace('id="vsp-profile"', 'id="vsp-profile-select"', 1)
    if before_new != before:
        before = before_new
        changed = True
        print("[OK] TAB 1: đổi id=\"vsp-profile\" -> id=\"vsp-profile-select\"")
else:
    print("[WARN] TAB 1: không thấy id=\"vsp-profile\"")

# 2) Trong phần TAB 2 (after): đổi id + for
repl_map = {
    'id="vsp-profile"': 'id="vsp-profile-runs"',
    'for="vsp-profile"': 'for="vsp-profile-runs"',
}
for old, new in repl_map.items():
    if old in after:
        after_new = after.replace(old, new, 1)
        if after_new != after:
            after = after_new
            changed = True
            print(f"[OK] TAB 2: {old} -> {new}")
    else:
        print(f"[WARN] TAB 2: không thấy {old}")

if changed:
    backup = path.with_suffix(path.suffix + ".bak_ids_fix_v1")
    backup.write_text(orig, encoding="utf-8")
    path.write_text(before + after, encoding="utf-8")
    print(f"[DONE] Ghi lại {path} (backup -> {backup.name})")
else:
    print("[SKIP] Không có thay đổi nào.")
PY

echo "[PATCH] Done."
