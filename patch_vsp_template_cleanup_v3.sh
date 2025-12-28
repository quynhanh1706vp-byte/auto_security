#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

targets=(
  "my_flask_app/templates/vsp_5tabs_full.html"
  "templates/index.html"
)

echo "[PATCH] VSP template cleanup v3"

python - << 'PY'
from pathlib import Path

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
targets = [
    ROOT / "my_flask_app/templates/vsp_5tabs_full.html",
    ROOT / "templates/index.html",
]

def remove_script_block(txt: str, marker: str):
    idx = txt.find(marker)
    if idx == -1:
        return txt, False
    # tìm <script ...> gần nhất trước marker
    start = txt.rfind("<script", 0, idx)
    end = txt.find("</script>", idx)
    if start == -1 or end == -1:
        return txt, False
    end += len("</script>")
    # nếu ngay trước <script> có comment <!-- ... marker ... --> thì cắt luôn
    comment_start = txt.rfind("<!--", 0, start)
    comment_end   = txt.find("-->", comment_start if comment_start != -1 else start)
    if comment_start != -1 and comment_end != -1 and comment_end < start:
        start = comment_start
    return txt[:start] + txt[end:], True

for path in targets:
    if not path.is_file():
        continue

    txt = path.read_text(encoding="utf-8")
    orig = txt

    changed = False

    # 1) Fix window.VSP_DATA = ;
    if "window.VSP_DATA" in txt and "window.VSP_DATA = ;" in txt:
        txt = txt.replace("window.VSP_DATA = ;", "window.VSP_DATA = {};")
        changed = True
        print(f"[FIX] {path.name}: sửa window.VSP_DATA = {{}}")

    # 2) remove KPI TOTAL AUTO block
    txt2, c2 = remove_script_block(txt, "// VSP KPI TOTAL AUTO")
    if c2:
        txt = txt2
        changed = True
        print(f"[FIX] {path.name}: xoá block VSP KPI TOTAL AUTO")

    # 3) remove VSP_KPI_BIND_V1 block
    txt2, c3 = remove_script_block(txt, "<!-- VSP_KPI_BIND_V1")
    if c3:
        txt = txt2
        changed = True
        print(f"[FIX] {path.name}: xoá block VSP_KPI_BIND_V1")

    # 4) remove old RUN button (/api/vsp/run_full)
    txt2, c4 = remove_script_block(txt, "// VSP RUN button -> call backend API")
    if c4:
        txt = txt2
        changed = True
        print(f"[FIX] {path.name}: xoá block RUN /api/vsp/run_full")

    # 5) remove VSP_RUNS_UI_V1 auto load
    txt2, c5 = remove_script_block(txt, "<!-- VSP_RUNS_UI_V1: auto load runs table")
    if c5:
        txt = txt2
        changed = True
        print(f"[FIX] {path.name}: xoá block VSP_RUNS_UI_V1")

    if changed and txt != orig:
        backup = path.with_suffix(path.suffix + ".bak_cleanup_v3")
        backup.write_text(orig, encoding="utf-8")
        path.write_text(txt, encoding="utf-8")
        print(f"[OK] Ghi lại {path} (backup -> {backup.name})")
    else:
        print(f"[SKIP] {path} không cần sửa hoặc không tìm thấy marker phù hợp.")
PY

echo "[PATCH] Done."
