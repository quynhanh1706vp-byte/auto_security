#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_watchdog_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_commercial_v2_1_${TS}"
echo "[BACKUP] $F.bak_commercial_v2_1_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_watchdog_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_WATCHDOG_COMMERCIAL_V2_1_SAFE"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

helpers = f"""
# === {MARK} ===
def _vsp_wd_now():
    import time
    return time.time()

def _vsp_wd_safe_mtime(path):
    try:
        import os
        return os.stat(path).st_mtime
    except Exception:
        return 0.0

def _vsp_wd_discover_ci_dir(state):
    import os, glob
    ci = (state.get("ci_run_dir") or "").strip()
    if ci and os.path.isdir(ci):
        return ci
    target = (state.get("target") or "").strip()
    cands = []
    if target and os.path.isdir(target):
        for pat in ("out_ci/VSP_CI_*", "ci/VSP_CI_OUTER/out_ci/VSP_CI_*", "out_ci/*"):
            cands += [d for d in glob.glob(os.path.join(target, pat)) if os.path.isdir(d)]
    # pick newest
    best = ""
    best_m = -1
    for d in cands:
        try:
            m = os.stat(d).st_mtime
        except Exception:
            continue
        if m > best_m:
            best, best_m = d, m
    return best

def _vsp_wd_discover_runner_log(ci_dir):
    import os, glob
    if not ci_dir:
        return ""
    p = os.path.join(ci_dir, "runner.log")
    if os.path.isfile(p):
        return p
    logs = glob.glob(os.path.join(ci_dir, "*.log")) + glob.glob(os.path.join(ci_dir, "**/*.log"), recursive=True)
    logs = [x for x in logs if os.path.isfile(x)]
    if not logs:
        return ""
    logs.sort(key=lambda x: os.stat(x).st_mtime, reverse=True)
    return logs[0]

def _vsp_wd_apply_commercial_safe(state):
    import os, time
    now = _vsp_wd_now()
    grace = int(os.environ.get("VSP_WD_GRACE_SEC","180"))
    boot  = int(os.environ.get("VSP_WD_BOOTSTRAP_SEC","240"))

    if not state.get("watchdog_start_ts"):
        state["watchdog_start_ts"] = now

    # fill ci_run_dir/runner_log if missing
    ci = _vsp_wd_discover_ci_dir(state)
    if ci and not state.get("ci_run_dir"):
        state["ci_run_dir"] = ci
    if state.get("ci_run_dir") and not state.get("runner_log"):
        rl = _vsp_wd_discover_runner_log(state.get("ci_run_dir") or "")
        if rl:
            state["runner_log"] = rl

    # Bootstrap/grace heartbeat "anti-kill-sai"
    start = float(state.get("watchdog_start_ts") or now)
    rl = state.get("runner_log") or ""
    has_log = bool(rl and os.path.isfile(rl))

    if (now - start) < max(grace, boot) and (not has_log):
        # set multiple candidate heartbeat keys to prevent stall-kill
        for k in ("last_heartbeat_ts","last_marker_ts","last_progress_ts","last_activity_ts","last_update_ts"):
            state[k] = now
        state["commercial_safe_reason"] = "BOOTSTRAP_GRACE_NOLOG"

    # If has log, propagate heartbeat from mtime
    if has_log:
        beat = _vsp_wd_safe_mtime(rl)
        if beat:
            for k in ("last_heartbeat_ts","last_marker_ts","last_activity_ts"):
                state[k] = max(float(state.get(k) or 0.0), beat)
# === END {MARK} ===
"""

# Insert helpers after imports
m = re.search(r"(\n(?:from|import)\s+[^\n]+)+\n", txt, flags=re.M)
if m:
    txt = txt[:m.end()] + helpers + "\n" + txt[m.end():]
else:
    txt = helpers + "\n" + txt

# Inject call after a likely "state = ..." load line (first occurrence after reading json/state)
anchors = [
    r"^\s*state\s*=\s*read_state\([^\n]+\)\s*$",
    r"^\s*state\s*=\s*load_state\([^\n]+\)\s*$",
    r"^\s*state\s*=\s*json\.load\([^\n]+\)\s*$",
    r"^\s*state\s*=\s*\{\}\s*$",
]
inject_done = False
for ap in anchors:
    mm = re.search(ap, txt, flags=re.M)
    if mm:
        # determine indent
        line = txt[mm.start():txt.find("\n", mm.start())]
        indent = re.match(r"^(\s*)", line).group(1)
        call = f"\n{indent}# === {MARK} APPLY ===\n{indent}try:\n{indent}    _vsp_wd_apply_commercial_safe(state)\n{indent}except Exception:\n{indent}    pass\n{indent}# === END {MARK} APPLY ===\n"
        insert_pos = mm.end()
        txt = txt[:insert_pos] + call + txt[insert_pos:]
        inject_done = True
        break

if not inject_done:
    # fallback: inject before first time.sleep(...) call
    mm = re.search(r"^\s*time\.sleep\([^\n]+\)\s*$", txt, flags=re.M)
    if not mm:
        raise SystemExit("[ERR] cannot find anchor (state-load or time.sleep) to inject commercial safe apply")
    indent = re.match(r"^(\s*)", txt[mm.start():txt.find('\n', mm.start())]).group(1)
    call = f"\n{indent}# === {MARK} APPLY ===\n{indent}try:\n{indent}    _vsp_wd_apply_commercial_safe(state)\n{indent}except Exception:\n{indent}    pass\n{indent}# === END {MARK} APPLY ===\n"
    txt = txt[:mm.start()] + call + txt[mm.start():]

p.write_text(txt, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
