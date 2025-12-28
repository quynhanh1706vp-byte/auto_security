from pathlib import Path
import re

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
p = ROOT / "vsp_demo_app.py"

txt = p.read_text(encoding="utf-8")
orig = txt

# 1) Gỡ các block run_full_scan cũ nếu có (INLINE + AUTOREG)
patterns_remove = [
    r"# --- INLINE ROUTE: /api/vsp/run_full_scan.*?# --- END INLINE ROUTE ---",
    r"# ===================== VSP RUN_FULL_SCAN AUTOREG V1 ==========================.*?# ================== END VSP RUN_FULL_SCAN AUTOREG V1 =========================",
]

for pat in patterns_remove:
    new_txt, n = re.subn(pat, "", txt, flags=re.DOTALL)
    if n:
        print(f"[INFO] Removed old run_full_scan block(s) pattern, count={n}")
    txt = new_txt

# 2) Tìm dòng app = Flask(...)
m = re.search(r'^(app\s*=\s*Flask\(.*?\))', txt, flags=re.MULTILINE)
if not m:
    print("[ERR] Không tìm thấy dòng 'app = Flask(...)' trong vsp_demo_app.py")
    exit(1)

insert_pos = m.end()

block = r'''

# ===================== VSP RUN_FULL_SCAN INLINE V2 ==========================
from pathlib import Path as _Path_for_run_full_scan_v2
import subprocess as _subprocess_for_run_full_scan_v2
from flask import jsonify as _jsonify_for_run_full_scan_v2, request as _request_for_run_full_scan_v2

# ui/vsp_demo_app.py -> SECURITY_BUNDLE ROOT
_ROOT_VSP_V2 = _Path_for_run_full_scan_v2(__file__).resolve().parents[1]

@app.route("/api/vsp/run_full_scan", methods=["POST"])
def api_run_full_scan_v2():
    """
    Trigger FULL scan từ UI.
    V2 – gắn trực tiếp vào app = Flask(...).
    """
    payload = _request_for_run_full_scan_v2.get_json(silent=True) or {}
    profile = payload.get("profile")
    source_root = payload.get("source_root")
    target_url = payload.get("target_url")

    script = _ROOT_VSP_V2 / "bin" / "vsp_selfcheck_full"

    if not script.is_file():
        return _jsonify_for_run_full_scan_v2(
            ok=False,
            error=f"Script not found: {script}",
        ), 500

    try:
        proc = _subprocess_for_run_full_scan_v2.Popen(
            [str(script)],
            cwd=str(_ROOT_VSP_V2),
            stdout=_subprocess_for_run_full_scan_v2.DEVNULL,
            stderr=_subprocess_for_run_full_scan_v2.DEVNULL,
        )
    except Exception as e:
        return _jsonify_for_run_full_scan_v2(
            ok=False,
            error=f"Failed to start scan: {e}",
        ), 500

    return _jsonify_for_run_full_scan_v2(
        ok=True,
        message="FULL scan started",
        cmd=str(script),
        pid=proc.pid,
        profile=profile,
        source_root=source_root,
        target_url=target_url,
    )
# ================== END VSP RUN_FULL_SCAN INLINE V2 =========================

'''

txt = txt[:insert_pos] + block + txt[insert_pos:]

if txt != orig:
    backup = p.with_suffix(p.suffix + ".bak_run_full_after_app_v2")
    backup.write_text(orig, encoding="utf-8")
    p.write_text(txt, encoding="utf-8")
    print(f"[OK] Patched vsp_demo_app.py, backup -> {backup.name}")
else:
    print("[INFO] Không có thay đổi với vsp_demo_app.py")
