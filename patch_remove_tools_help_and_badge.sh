#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

python3 - <<'PY'
import os, re

root = "/home/test/Data/SECURITY_BUNDLE/ui"

def patch_file(rel):
    path = os.path.join(root, rel)
    if not os.path.exists(path):
        print(f"[INFO] Bỏ qua {rel} (không tồn tại).")
        return

    txt = open(path, encoding="utf-8").read()
    orig = txt
    changed = False

    # 1) Bỏ đoạn <p> ngay sau "SETTINGS – TOOL CONFIG"
    marker = "SETTINGS – TOOL CONFIG"
    idx = txt.find(marker)
    if idx != -1:
        p_start = txt.find("<p", idx)
        if p_start != -1:
            p_end = txt.find("</p>", p_start)
            if p_end != -1:
                p_end += len("</p>")
                print(f"[OK] {rel}: bỏ đoạn <p> mô tả ngay sau 'SETTINGS – TOOL CONFIG'.")
                txt = txt[:p_start] + txt[p_end:]
                changed = True

    # 2) Bỏ mọi <span ...> chứa 'Tools enabled:'
    span_pat = re.compile(
        r"<span[^>]*>[^<]*Tools enabled:[^<]*</span>",
        re.IGNORECASE,
    )
    txt2, n = span_pat.subn("", txt)
    if n:
        print(f"[OK] {rel}: bỏ {n} span chứa 'Tools enabled:'.")
        txt = txt2
        changed = True

    if changed and txt != orig:
        with open(path, "w", encoding="utf-8") as f:
            f.write(txt)
    else:
        print(f"[INFO] {rel}: không có gì để sửa hoặc đã sạch.")

for rel in [
    "templates/index.html",
    "app.py",
    "app_ui_final_20251115.py",
]:
    patch_file(rel)
PY
