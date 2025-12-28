import subprocess
import datetime
import os
from pathlib import Path
from typing import List, Dict, Optional

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out"

VSP_CI_OUTER_SCRIPT = ROOT / "VSP_CI_OUTER" / "vsp_ci_outer_full_v1.sh"
RUN_FULL_EXT_SCRIPT = ROOT / "bin" / "run_vsp_full_ext.sh"


def make_timestamp() -> str:
    return datetime.datetime.now().strftime("%Y%m%d_%H%M%S")


def start_subprocess_background(
    cmd: List[str], env_extra: Optional[Dict[str, str]] = None
) -> int:
    """
    Chạy lệnh nền, không block request.
    Trả về PID process con (0 nếu lỗi).
    """
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)

    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(ROOT),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return proc.pid
    except Exception as e:
        print("[VSP_UTIL] Failed to start subprocess:", e)
        return 0


def start_vsp_full_run_local(
    target_path: str,
    profile: str = "FULL_EXT",
    run_id_hint: Optional[str] = None,
) -> Dict[str, object]:
    """
    Quy ước:
    - Nếu có VSP_CI_OUTER/vsp_ci_outer_full_v1.sh thì ưu tiên gọi CI_OUTER.
    - Nếu không, fallback bin/run_vsp_full_ext.sh.
    - Trả về dict: {ok, pid, script, run_id_hint}.
    """
    script: Optional[Path] = None
    if VSP_CI_OUTER_SCRIPT.exists():
        script = VSP_CI_OUTER_SCRIPT
    elif RUN_FULL_EXT_SCRIPT.exists():
        script = RUN_FULL_EXT_SCRIPT

    if script is None:
        return {
            "ok": False,
            "error": f"Không tìm thấy script CI_OUTER ({VSP_CI_OUTER_SCRIPT}) hoặc FULL_EXT ({RUN_FULL_EXT_SCRIPT}).",
            "pid": 0,
            "script": None,
            "run_id_hint": run_id_hint,
        }

    if not run_id_hint:
        run_id_hint = f"RUN_VSP_UI_LOCAL_{make_timestamp()}"

    env_extra = {
        "VSP_TARGET_PATH": target_path,
        "VSP_PROFILE": profile,
        "VSP_RUN_ID_HINT": run_id_hint,
    }

    pid = start_subprocess_background([str(script), target_path], env_extra=env_extra)

    if pid <= 0:
        return {
            "ok": False,
            "error": "Không start được subprocess.",
            "pid": 0,
            "script": str(script),
            "run_id_hint": run_id_hint,
        }

    return {
        "ok": True,
        "pid": pid,
        "script": str(script),
        "run_id_hint": run_id_hint,
    }
