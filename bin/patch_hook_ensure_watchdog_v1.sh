#!/usr/bin/env bash
set -euo pipefail
H="run_api/vsp_watchdog_hook_v1.py"
[ -f "$H" ] || { echo "[ERR] missing $H"; exit 1; }
cp -f "$H" "$H.bak_ensurewd_$(date +%Y%m%d_%H%M%S)"
echo "[BACKUP] $H.bak_ensurewd_*"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_watchdog_hook_v1.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# Inject helpers: _is_alive + _ensure_watchdog (record watchdog_pid)
if "_ensure_watchdog(" not in s:
    s = s.replace("def _spawn_watchdog(state_path: Path) -> None:", """
def _is_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False

def _ensure_watchdog(state_path: Path, st: dict) -> dict:
    # If watchdog_pid missing/dead -> spawn new and record pid
    wp = int(st.get("watchdog_pid") or 0)
    if _is_alive(wp):
        return st
    wd = Path(__file__).resolve().parent / "vsp_watchdog_v1.py"
    if not wd.exists():
        return st
    try:
        p = subprocess.Popen(
            ["python3", str(wd), "--state", str(state_path), "--tick", "2"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        st["watchdog_pid"] = int(p.pid)
    except Exception:
        pass
    return st

def _spawn_watchdog(state_path: Path) -> None:
""")

# In lazy-create status path: after writing state, call ensure_watchdog
s = re.sub(
    r"_atomic_write\(sp,\s*st\)\s*\n\s*_spawn_watchdog\(sp\)",
    "_atomic_write(sp, st)\n                    st = _ensure_watchdog(sp, st)\n                    _atomic_write(sp, st)",
    s,
    count=1
)

# In run_v1 wrapper path: after writing state, ensure watchdog too
s = re.sub(
    r"_atomic_write\(sp,\s*st\)\s*\n\s*_spawn_watchdog\(sp\)",
    "_atomic_write(sp, st)\n                st = _ensure_watchdog(sp, st)\n                _atomic_write(sp, st)",
    s,
    count=1
)

p.write_text(s, encoding="utf-8")
print("[OK] patched ensure-watchdog into hook")
PY

python3 -m py_compile run_api/vsp_watchdog_hook_v1.py
echo "[OK] py_compile hook OK"
