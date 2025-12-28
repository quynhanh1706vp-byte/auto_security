#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
BK="${APP}.bak_run_status_safe_v1_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BK"
echo "[BACKUP] $BK"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# nếu đã có route thì thôi
if "/api/vsp/run_status/<req_id>" in txt or "def api_vsp_run_status(" in txt:
    print("[SKIP] run_status already exists")
    raise SystemExit(0)

# ensure imports exist (append-only, không sửa import line phức tạp)
def ensure_line(line):
    global txt
    if line not in txt:
        # chèn sau block import đầu tiên cho sạch
        m = re.search(r"(?:^import .*?$|^from .*? import .*?$)(?:\n(?:import .*?$|from .*? import .*?$))*\n", txt, flags=re.M)
        if m:
            ins = m.end()
            txt = txt[:ins] + line + "\n" + txt[ins:]
        else:
            txt = line + "\n" + txt

ensure_line("import traceback")
ensure_line("import re")
ensure_line("from pathlib import Path")
# jsonify: nếu file đã `from flask import ...` thì không thêm; nếu chưa thì thêm minimal
if re.search(r"from\s+flask\s+import\s+.*\bjsonify\b", txt) is None:
    ensure_line("from flask import jsonify")

# append block at EOF (không chen trước if __main__)
block = r'''

# ============================================================
# VSP UI -> CI: Status endpoint for polling (Run Scan Now UI)
# GET /api/vsp/run_status/<req_id>
# ============================================================
def _vsp_tail_lines(p: str, n: int = 80):
    try:
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.read().splitlines()
        return lines[-n:]
    except Exception as e:
        return [f"[run_status][ERR] cannot read log: {e}"]

def _vsp_parse_status_from_log(lines):
    status = "PENDING"
    final_rc = None
    ci_run_id = None
    gate = None

    rx_outer = re.compile(r"\[VSP_CI_OUTER\].*?\bRUN_ID\b\s*=\s*(VSP_CI_\d{8}_\d{6})")
    rx_gate_final = re.compile(r"\[VSP_CI_GATE\].*?\bFinal RC\b\s*:\s*(\-?\d+)")
    rx_pipe_end = re.compile(r"\[VSP_UI_RUN\].*?Pipeline kết thúc với RC=(\-?\d+)")
    rx_gate_pass = re.compile(r"\[VSP_CI_GATE\].*?\bGATE PASS\b")
    rx_gate_fail = re.compile(r"\[VSP_CI_GATE\].*?\bGATE FAIL\b")

    saw_any = False
    for ln in lines:
        if "[VSP_" in ln:
            saw_any = True
        m = rx_outer.search(ln)
        if m and not ci_run_id:
            ci_run_id = m.group(1)
        if rx_gate_pass.search(ln):
            gate = "PASS"
        if rx_gate_fail.search(ln):
            gate = "FAIL"
        m = rx_gate_final.search(ln)
        if m:
            final_rc = int(m.group(1))
        m = rx_pipe_end.search(ln)
        if m:
            final_rc = int(m.group(1))

    if not saw_any:
        status = "PENDING"
    else:
        status = "RUNNING"
        if final_rc is not None:
            status = "DONE" if final_rc == 0 else "FAILED"

    return status, ci_run_id, gate, final_rc

def _vsp_try_read_has_findings(ci_run_id: str):
    if not ci_run_id:
        return None
    vsp_run_id = "RUN_" + ci_run_id.replace("VSP_CI_", "VSP_CI_")
    vsp_flag = Path("/home/test/Data/SECURITY_BUNDLE/out") / vsp_run_id / "report" / "ci_flag_has_findings.env"
    for fp in [vsp_flag]:
        try:
            if fp.is_file():
                for ln in fp.read_text(encoding="utf-8", errors="ignore").splitlines():
                    ln = ln.strip()
                    if ln.startswith("has_findings="):
                        return int(ln.split("=", 1)[1].strip())
        except Exception:
            continue
    return None

@app.route("/api/vsp/run_status/<req_id>", methods=["GET"])
def api_vsp_run_status(req_id):
    try:
        log_dir = Path("/home/test/Data/SECURITY_BUNDLE/out_ci/ui_triggers")
        log_path = log_dir / f"{req_id}.log"
        if not log_path.is_file():
            return jsonify({"ok": False, "error": f"REQ log not found: {str(log_path)}"}), 404

        lines = _vsp_tail_lines(str(log_path), n=90)
        status, ci_run_id, gate, final_rc = _vsp_parse_status_from_log(lines)

        has_findings = _vsp_try_read_has_findings(ci_run_id)
        flag = {}
        if has_findings is not None:
            flag["has_findings"] = has_findings

        return jsonify({
            "ok": True,
            "request_id": req_id,
            "status": status,
            "ci_run_id": ci_run_id,
            "gate": gate,
            "final": final_rc,
            "flag": flag,
            "tail": lines[-60:]
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "trace": traceback.format_exc()}), 500
# ============================================================
'''

txt = txt.rstrip() + "\n" + block + "\n"
p.write_text(txt, encoding="utf-8")
print("[OK] appended run_status block safely at EOF")
PY

python3 -m py_compile "$APP" && echo "[OK] Python compile OK"
