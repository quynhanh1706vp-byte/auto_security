#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

python - << 'PY'
from pathlib import Path
import textwrap

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")

# 1) Tìm file .py nào có string "/api/vsp/dashboard_v3"
candidates = []
for p in root.rglob("*.py"):
    try:
        txt = p.read_text(encoding="utf-8")
    except Exception:
        continue
    if "/api/vsp/dashboard_v3" in txt:
        candidates.append(p)

if not candidates:
    print("[ERR] Không tìm thấy file .py nào chứa '/api/vsp/dashboard_v3'.")
    raise SystemExit(1)

if len(candidates) > 1:
    print("[ERR] Tìm thấy nhiều hơn 1 file chứa dashboard_v3:")
    for c in candidates:
        print("  -", c)
    print("Hãy mở file phù hợp và báo lại để patch chính xác.")
    raise SystemExit(1)

target = candidates[0]
print("[PATCH] Target file:", target)

# 2) Backup
bak = target.with_suffix(target.suffix + ".bak_dashboard_autopatch")
target.write_text(target.read_text(encoding="utf-8"), encoding="utf-8")  # ensure readable
target.replace(bak)
bak.replace(target)  # Chỉ để chắc chắn file tồn tại; backup sẽ do copy riêng bên ngoài shell

# Thực backup thật sự
bak2 = target.with_name(target.name + ".bak_dashboard_autopatch")
bak2.write_text(target.read_text(encoding="utf-8"), encoding="utf-8")
print("[BACKUP] ->", bak2)

txt = target.read_text(encoding="utf-8")

# 3) Đảm bảo ROOT và load_summary có mặt (nếu chưa thì chèn thêm)
insert_root = False
insert_load = False

if "ROOT =" not in txt:
    insert_root = True
if "def load_summary(" not in txt:
    insert_load = True

prefix_inserts = ""
if insert_root:
    prefix_inserts += textwrap.dedent("""
    from pathlib import Path

    ROOT = Path(__file__).resolve().parents[2]
    """)
if insert_load:
    prefix_inserts += textwrap.dedent("""
    import json

    def load_summary(run_dir: Path):
        p = run_dir / "report" / "summary_unified.json"
        if not p.is_file():
            return None
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:
            print("[VSP_DASHBOARD_V3] Lỗi load", p, "=>", e)
            return None
    """)

if prefix_inserts:
    # chèn ngay sau import đầu tiên
    idx = txt.find("\n")
    if idx != -1:
        txt = txt[:idx+1] + prefix_inserts.lstrip("\n") + txt[idx+1:]
    else:
        txt = prefix_inserts + "\n" + txt

# 4) Thay hàm dashboard_v3
marker = "def dashboard_v3("
idx = txt.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy 'def dashboard_v3(' trong", target)
    raise SystemExit(1)

# Tìm điểm kết thúc function: hàm tiếp theo bắt đầu ở cột 0 với "def " hoặc "@"
end = txt.find("\ndef ", idx + 1)
next_dec = txt.find("\n@", idx + 1)
candidates_end = [pos for pos in (end, next_dec) if pos != -1]
if candidates_end:
    end_pos = min(candidates_end)
else:
    end_pos = len(txt)

new_func = textwrap.dedent("""
    def dashboard_v3():
        \"\"\"Dashboard V3 – trả summary_unified.json + meta.

        Response:
        {
          "ok": true,
          "latest_run_id": "RUN_VSP_FULL_EXT_...",
          "runs_recent": [...],
          ... toàn bộ field trong summary_unified.json
        }
        \"\"\"
        from flask import jsonify  # đảm bảo import sẵn

        out_dir = ROOT / "out"
        runs = sorted(out_dir.glob("RUN_VSP_FULL_EXT_*"), reverse=True)
        if not runs:
            return jsonify(ok=False, error="No runs found")

        latest = runs[0]
        summary = load_summary(latest) if 'load_summary' in globals() else None
        if not summary:
            return jsonify(
                ok=False,
                latest_run_id=latest.name,
                error="summary_unified.json not found or invalid",
            )

        resp = {
            "ok": True,
            "latest_run_id": latest.name,
            "runs_recent": [r.name for r in runs[:20]],
        }

        if isinstance(summary, dict):
            resp.update(summary)

        return jsonify(resp)
    """)

txt = txt[:idx] + new_func.lstrip("\n") + "\n" + txt[end_pos:].lstrip("\n")

target.write_text(txt, encoding="utf-8")
print("[OK] Đã patch lại hàm dashboard_v3() theo kiểu passthrough.")
PY
