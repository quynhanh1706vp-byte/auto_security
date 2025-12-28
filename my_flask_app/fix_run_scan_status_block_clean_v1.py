from pathlib import Path

p = Path("api_vsp_dashboard_v2.py")
text = p.read_text(encoding="utf-8")

marker = "Trả trạng thái RUN scan từ UI: IDLE / IN_PROGRESS / DONE."
idx = text.find(marker)

if idx == -1:
    print("[ERR] Không tìm thấy marker trong file, không sửa được.")
    raise SystemExit(1)

# Tìm ngược lại tới decorator của route status
route_start = text.rfind('@bp_vsp_dashboard_v2.route("/api/vsp/run_scan_status"', 0, idx)
if route_start == -1:
    route_start = text.rfind('@bp.route("/api/vsp/run_scan_status"', 0, idx)

if route_start == -1:
    print("[ERR] Không tìm thấy decorator /api/vsp/run_scan_status trước marker.")
    raise SystemExit(1)

head = text[:route_start]

backup = p.with_suffix(p.suffix + ".bak_fix_run_scan_status_block_clean_v1")
backup.write_text(text, encoding="utf-8")
print("[BACKUP] ->", backup)

append_block = '''

@bp_vsp_dashboard_v2.route("/api/vsp/run_scan_status", methods=["GET"])
def api_vsp_run_scan_status():
    """Trả trạng thái RUN scan từ UI: IDLE / IN_PROGRESS / DONE."""
    from flask import jsonify
    from pathlib import Path

    ROOT = Path(__file__).resolve().parents[2]
    out_dir = ROOT / "out"
    log_path = out_dir / "vsp_run_from_settings.log"
    last_vsp_file = out_dir / "last_vsp_run.txt"

    started_run_id = None
    if log_path.is_file():
        try:
            lines = log_path.read_text(encoding="utf-8", errors="ignore").splitlines()
            for line in reversed(lines):
                if "RUN_DIR" in line and "RUN_VSP_FULL_EXT_" in line:
                    # ví dụ: [i] RUN_DIR = /.../out/RUN_VSP_FULL_EXT_20251203_114325
                    part = line.split("RUN_VSP_FULL_EXT_", 1)[1]
                    token = part.strip().split()[0]
                    tail = token.split("/")[-1]
                    started_run_id = "RUN_VSP_FULL_EXT_" + tail.replace("RUN_VSP_FULL_EXT_", "")
                    break
        except Exception:
            pass

    last_done_run_id = None
    if last_vsp_file.is_file():
        try:
            last_done_run_id = last_vsp_file.read_text(encoding="utf-8", errors="ignore").strip()
        except Exception:
            pass

    if not started_run_id:
        status = "IDLE"
    elif started_run_id == last_done_run_id:
        status = "DONE"
    else:
        run_dir = out_dir / started_run_id
        summary = run_dir / "report" / "summary_unified.json"
        if summary.is_file():
            status = "DONE"
        else:
            status = "IN_PROGRESS"

    return jsonify({
        "ok": True,
        "status": status,
        "started_run_id": started_run_id,
        "last_done_run_id": last_done_run_id,
    })

'''

new_text = head.rstrip() + append_block + "\n"
p.write_text(new_text, encoding="utf-8")
print("[OK] Đã xoá block lỗi và ghi lại api_vsp_run_scan_status() sạch.")
