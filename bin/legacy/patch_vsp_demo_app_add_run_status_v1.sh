#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"

if [ ! -f "$APP" ]; then
  echo "[PATCH][ERR] Missing: $APP"
  exit 1
fi

BK="${APP}.bak_run_status_v1_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BK"
echo "[BACKUP] $BK"

# Nếu đã có route thì skip
if grep -qE 'api_vsp_run_status|/api/vsp/run_status' "$APP"; then
  echo "[PATCH] run_status route already present. Skip."
  exit 0
fi

python3 - << 'PY'
from pathlib import Path
import re

app = Path("vsp_demo_app.py")
txt = app.read_text(encoding="utf-8", errors="ignore")

# Chèn import nếu thiếu
need_imports = [
  ("import os", "import os"),
  ("import re", "import re"),
  ("from pathlib import Path", "from pathlib import Path"),
]
for key, line in need_imports:
  if key not in txt:
    # chèn sau các import đầu file (fallback: prepend)
    m = re.search(r"(^import .*?$|^from .*? import .*?$)", txt, flags=re.M)
    if m:
      pos = m.end()
      txt = txt[:pos] + "\n" + line + txt[pos:]
    else:
      txt = line + "\n" + txt

block = r'''

# ============================================================
# VSP UI -> CI: Status endpoint for polling (Run Scan Now UI)
# GET /api/vsp/run_status/<req_id>
# - Reads UI trigger log: SECURITY_BUNDLE/out_ci/ui_triggers/UIREQ_*.log
# - Parses ci_run_id, gate, final rc
# - Returns tail log lines
# ============================================================
def _vsp_tail_lines(p: str, n: int = 80):
    try:
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.read().splitlines()
        return lines[-n:]
    except Exception as e:
        return [f"[run_status][ERR] cannot read log: {e}"]

def _vsp_parse_status_from_log(lines):
    # defaults
    status = "PENDING"
    final_rc = None
    ci_run_id = None
    gate = None

    # Parse ci_run_id from OUTER banner
    rx_run = re.compile(r"\bRUN_ID\b\s*=\s*(VSP_CI_\d{8}_\d{6})")
    rx_run2 = re.compile(r"\bRUN_ID\b\s*=\s*(VSP_CI_\d{8}_\d{6})")
    rx_outer = re.compile(r"\[VSP_CI_OUTER\].*?\bRUN_ID\b\s*=\s*(VSP_CI_\d{8}_\d{6})")
    rx_pipe_end = re.compile(r"\[VSP_UI_RUN\].*?Pipeline kết thúc với RC=(\-?\d+)")
    rx_gate_final = re.compile(r"\[VSP_CI_GATE\].*?\bFinal RC\b\s*:\s*(\-?\d+)")
    rx_runner_rc = re.compile(r"\[VSP_CI_GATE\].*?Runner kết thúc với RC=(\-?\d+)")
    rx_gate_pass = re.compile(r"\[VSP_CI_GATE\].*?\bGATE PASS\b")
    rx_gate_fail = re.compile(r"\[VSP_CI_GATE\].*?\bGATE FAIL\b")

    saw_start = False
    for ln in lines:
        if "[VSP_UI_RUN]" in ln or "[VSP_CI_OUTER]" in ln or "[VSP_CI_GATE]" in ln:
            saw_start = True

        m = rx_outer.search(ln) or rx_run.search(ln) or rx_run2.search(ln)
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

        # Nếu runner chết sớm mà chưa có Final RC
        if final_rc is None:
            m = rx_runner_rc.search(ln)
            if m:
                final_rc = int(m.group(1))

    if not saw_start:
        status = "PENDING"
    else:
        # Có start
        status = "RUNNING"
        if final_rc is not None:
            status = "DONE" if final_rc == 0 else "FAILED"

    return status, ci_run_id, gate, final_rc

def _vsp_try_read_has_findings(ci_run_id: str):
    # ưu tiên nếu đã sync về VSP core: out/RUN_VSP_CI_x/report/ci_flag_has_findings.env
    if not ci_run_id:
        return None

    vsp_run_id = "RUN_" + ci_run_id.replace("VSP_CI_", "VSP_CI_")
    vsp_flag = Path("/home/test/Data/SECURITY_BUNDLE/out") / vsp_run_id / "report" / "ci_flag_has_findings.env"
    # fallback: có thể có flag trong CI_RUN_DIR/report/ci_flag_has_findings.env (nếu bạn tạo ở outer)
    ci_flag = Path("/home/test/Data/SECURITY-10-10-v4/out_ci") / ci_run_id / "report" / "ci_flag_has_findings.env"

    for fp in [vsp_flag, ci_flag]:
        try:
            if fp.is_file():
                data = fp.read_text(encoding="utf-8", errors="ignore").splitlines()
                for ln in data:
                    ln = ln.strip()
                    if ln.startswith("has_findings="):
                        return int(ln.split("=", 1)[1].strip())
        except Exception:
            continue
    return None

@app.route("/api/vsp/run_status/<req_id>", methods=["GET"])
def api_vsp_run_status(req_id):
    # req_id expected like UIREQ_YYYYmmdd_HHMMSS_pid
    log_dir = Path("/home/test/Data/SECURITY_BUNDLE/out_ci/ui_triggers")
    log_path = log_dir / f"{req_id}.log"

    if not log_path.is_file():
        return jsonify({
            "ok": False,
            "error": f"REQ log not found: {log_path}"
        }), 404

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
        "tail": lines[-60:]  # UI show last 60 lines
    })
# ============================================================
'''

# Chèn block trước if __name__ == "__main__" nếu có, không thì append cuối file
m = re.search(r"^if\s+__name__\s*==\s*[\"']__main__[\"']\s*:\s*$", txt, flags=re.M)
if m:
    insert_at = m.start()
    txt = txt[:insert_at] + block + "\n" + txt[insert_at:]
else:
    txt = txt.rstrip() + "\n" + block + "\n"

app.write_text(txt, encoding="utf-8")
print("[OK] patched run_status into vsp_demo_app.py")
PY

echo "[DONE] Added GET /api/vsp/run_status/<req_id> (polling endpoint)."
echo "      Restart UI (8910) then test:"
echo "      curl -s http://localhost:8910/api/vsp/run_status/UIREQ_.... | jq"
