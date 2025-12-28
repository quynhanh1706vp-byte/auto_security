#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_watchdog_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_commercial_v2_${TS}"
echo "[BACKUP] $F.bak_commercial_v2_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_watchdog_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_WATCHDOG_COMMERCIAL_V2"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Add helper block near top (after imports)
m = re.search(r"^\s*import\s+.*$", txt, flags=re.M)
if not m:
    print("[ERR] cannot find imports area")
    raise SystemExit(2)

insert_helpers = r"""
# === {MARK} HELPERS ===
from datetime import datetime

def _now_ts() -> float:
    return time.time()

def _safe_stat_mtime(path: str) -> float:
    try:
        return os.stat(path).st_mtime
    except Exception:
        return 0.0

def _is_dir(path: str) -> bool:
    try:
        return os.path.isdir(path)
    except Exception:
        return False

def _pick_newest_dir(glob_list):
    best = None
    best_m = -1.0
    for d in glob_list:
        try:
            m = os.stat(d).st_mtime
        except Exception:
            continue
        if m > best_m:
            best, best_m = d, m
    return best

def _discover_ci_run_dir(state: dict) -> str:
    # Prefer existing
    ci = state.get("ci_run_dir") or ""
    if ci and _is_dir(ci):
        return ci

    # Candidates from target path
    target = (state.get("target") or "").strip()
    candidates = []

    # If target is a project root, look for out_ci/VSP_CI_*
    if target and _is_dir(target):
        for pat in ("out_ci/VSP_CI_*", "ci/VSP_CI_OUTER/out_ci/VSP_CI_*", "out_ci/ui_req_state", "out_ci/*"):
            try:
                import glob
                candidates += [d for d in glob.glob(os.path.join(target, pat)) if _is_dir(d)]
            except Exception:
                pass

    # Also try common places relative to this repo (best effort)
    try:
        root = Path(__file__).resolve().parents[1]
        for pat in ("out_ci/VSP_CI_*",):
            import glob
            candidates += [d for d in glob.glob(str(root / pat)) if _is_dir(d)]
    except Exception:
        pass

    # Prefer dirs that have runner.log / SUMMARY / findings
    preferred = []
    for d in candidates:
        if os.path.isfile(os.path.join(d, "runner.log")):
            preferred.append(d)
        elif os.path.isfile(os.path.join(d, "SUMMARY.txt")):
            preferred.append(d)
        elif os.path.isfile(os.path.join(d, "findings_unified.json")) or os.path.isfile(os.path.join(d, "summary_unified.json")):
            preferred.append(d)

    best = _pick_newest_dir(preferred) or _pick_newest_dir(candidates)
    return best or ""

def _discover_runner_log(ci_run_dir: str) -> str:
    if not ci_run_dir:
        return ""
    p = os.path.join(ci_run_dir, "runner.log")
    if os.path.isfile(p):
        return p
    # fallback: newest *.log
    try:
        import glob
        logs = glob.glob(os.path.join(ci_run_dir, "*.log")) + glob.glob(os.path.join(ci_run_dir, "**/*.log"), recursive=True)
        logs = [x for x in logs if os.path.isfile(x)]
        if not logs:
            return ""
        logs.sort(key=lambda x: os.stat(x).st_mtime, reverse=True)
        return logs[0]
    except Exception:
        return ""

def _commercial_should_kill(state: dict, now_ts: float) -> tuple[bool,str]:
    # Grace + bootstrap: don't kill too early when just spawned or when no log yet
    grace_sec = int(os.environ.get("VSP_WD_GRACE_SEC", "120"))
    bootstrap_sec = int(os.environ.get("VSP_WD_BOOTSTRAP_SEC", "180"))
    stall = int(state.get("stall_timeout_sec") or os.environ.get("VSP_STALL_TIMEOUT_SEC","600"))
    total = int(state.get("total_timeout_sec") or os.environ.get("VSP_TOTAL_TIMEOUT_SEC","7200"))

    start_ts = float(state.get("watchdog_start_ts") or 0.0)
    if start_ts <= 0:
        start_ts = now_ts
        state["watchdog_start_ts"] = start_ts

    # total timeout
    if now_ts - start_ts > total:
        return True, f"TOTAL_TIMEOUT>{total}s"

    # bootstrap protection when runner_log not ready
    runner_log = state.get("runner_log") or ""
    has_log = bool(runner_log and os.path.isfile(runner_log))
    if not has_log and (now_ts - start_ts) < max(grace_sec, bootstrap_sec):
        return False, "BOOTSTRAP_GRACE"

    # heartbeat: consider log mtime as heartbeat
    beat_ts = float(state.get("last_heartbeat_ts") or 0.0)
    if has_log:
        beat_ts = max(beat_ts, _safe_stat_mtime(runner_log))

    # also treat stage/progress updates as heartbeat
    beat_ts = max(beat_ts, float(state.get("last_progress_ts") or 0.0), start_ts)
    state["last_heartbeat_ts"] = beat_ts

    # stall protection after grace
    if (now_ts - start_ts) < grace_sec:
        return False, "GRACE"

    if now_ts - beat_ts > stall:
        return True, f"STALL>{stall}s"
    return False, "OK"

def _commercial_finalize_sync(state: dict):
    # Always try sync once when final/killed and ci_run_dir known
    if state.get("finalize_done"):
        return
    ci = state.get("ci_run_dir") or ""
    if not ci or not os.path.isdir(ci):
        return

    # Prefer SECURITY_BUNDLE/bin/vsp_ci_sync_to_vsp_v1.sh
    try:
        root = Path(__file__).resolve().parents[1]  # .../ui
        sb = root.parent  # .../SECURITY_BUNDLE
        sync = sb / "bin" / "vsp_ci_sync_to_vsp_v1.sh"
        if not sync.is_file():
            return
        import subprocess
        res = subprocess.run([str(sync), ci], capture_output=True, text=True)
        state["finalize_done"] = True
        state["finalize_sync_rc"] = res.returncode
        state["finalize_sync_out"] = (res.stdout or "")[-4000:]
        state["finalize_sync_err"] = (res.stderr or "")[-4000:]
    except Exception as e:
        state["finalize_done"] = True
        state["finalize_sync_rc"] = 999
        state["finalize_sync_err"] = f"EXC: {e}"
# === END {MARK} HELPERS ===
""".replace("{MARK}", MARK)

# Insert helpers after the last import block
# Find end of consecutive imports
lines = txt.splitlines(True)
last_import_idx = 0
for i, ln in enumerate(lines):
    if re.match(r"^\s*(import|from)\s+\S+", ln):
        last_import_idx = i
    elif i > 0 and last_import_idx and ln.strip() and not re.match(r"^\s*(import|from)\s+\S+", ln):
        break
insert_at = last_import_idx + 1
lines.insert(insert_at, insert_helpers + "\n")
txt2 = "".join(lines)

# Patch main loop: wherever it updates state each tick, add CI dir/log discovery + commercial kill decision + finalize/sync hook.
# Heuristic: find place that loads state and then writes it back in a loop.
# We'll inject near any occurrence of: state["killed"] or kill logic.
needle = r"(state\.get\(\s*['\"]killed['\"]\s*\)|state\[['\"]killed['\"]\])"
m2 = re.search(needle, txt2)
if not m2:
    # fallback: inject near end of loop: search for write_state(...) call
    m2 = re.search(r"(write_state\([^)]*\)\s*)", txt2)
if not m2:
    print("[ERR] cannot find loop anchor to inject commercial logic")
    raise SystemExit(3)

inject_loop = r"""
# === {MARK} LOOP_INJECT ===
try:
    # fill ci_run_dir/runner_log if missing (fallback/heuristic)
    _ci = _discover_ci_run_dir(state)
    if _ci and not state.get("ci_run_dir"):
        state["ci_run_dir"] = _ci
    if state.get("ci_run_dir") and not state.get("runner_log"):
        _rl = _discover_runner_log(state.get("ci_run_dir") or "")
        if _rl:
            state["runner_log"] = _rl
    # commercial kill decision (grace + bootstrap + heartbeat)
    _now = _now_ts()
    _kill, _why = _commercial_should_kill(state, _now)
    state["kill_reason"] = state.get("kill_reason") or _why
    if _kill and not state.get("killed"):
        state["killed"] = True
        state["kill_reason"] = _why
        # NOTE: existing code should perform actual kill; we only set flags here safely.
    # finalize/sync always when final or killed
    if state.get("killed") or state.get("final"):
        _commercial_finalize_sync(state)
except Exception as _e:
    state["commercial_v2_err"] = str(_e)
# === END {MARK} LOOP_INJECT ===
""".replace("{MARK}", MARK)

# Insert before the first anchor match line (best effort)
pos = m2.start()
txt3 = txt2[:pos] + inject_loop + "\n" + txt2[pos:]

p.write_text(txt3, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
