#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_watchdog_finalize_${TS}"
echo "[BACKUP] $PYF.bak_watchdog_finalize_${TS}"

python3 - << 'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_WATCHDOG_KILL_FINALIZE_V5"
if MARK in txt:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) Append helpers
helpers = r'''

# === VSP_WATCHDOG_KILL_FINALIZE_V5 ===
import os as _os
import time as _time
import signal as _signal
import subprocess as _subprocess
from pathlib import Path as _Path

def _vsp_bundle_root_v5():
  # .../SECURITY_BUNDLE/ui/run_api/vsp_run_api_v1.py -> parents[2] = SECURITY_BUNDLE
  try:
    return _Path(__file__).resolve().parents[2]
  except Exception:
    return _Path.cwd()

def _vsp_uireq_dir_v5():
  ui_root = _Path(__file__).resolve().parents[1]  # .../ui
  d = ui_root / "out_ci" / "uireq_v1"
  d.mkdir(parents=True, exist_ok=True)
  return d

def _vsp_state_path_v5(req_id: str):
  return _vsp_uireq_dir_v5() / f"{req_id}.json"

def _vsp_load_state_v5(req_id: str):
  import json
  f = _vsp_state_path_v5(req_id)
  if not f.exists():
    return {}
  try:
    return json.loads(f.read_text(encoding="utf-8", errors="ignore") or "{}")
  except Exception:
    return {}

def _vsp_save_state_v5(req_id: str, st: dict):
  import json
  f = _vsp_state_path_v5(req_id)
  st = dict(st or {})
  st["req_id"] = req_id
  f.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")

def _vsp_kill_pgid_v5(pid: int):
  # Prefer kill process group (if started with setsid). Fallback kill pid.
  try:
    _os.killpg(int(pid), _signal.SIGTERM)
    return True, "SIGTERM(pgid)"
  except Exception:
    try:
      _os.kill(int(pid), _signal.SIGTERM)
      return True, "SIGTERM(pid)"
    except Exception as e:
      return False, f"kill_failed:{e}"

def _vsp_read_degraded_v5(ci_run_dir: str):
  try:
    f = _Path(ci_run_dir) / "vsp_degraded.env"
    if not f.exists():
      f = _Path(ci_run_dir) / "out" / "vsp_degraded.env"
    if not f.exists():
      return 0, ""
    degraded = 0
    reasons = ""
    for line in f.read_text(encoding="utf-8", errors="ignore").splitlines():
      if line.startswith("degraded="):
        try: degraded = int(line.split("=",1)[1].strip() or "0")
        except: degraded = 0
      if line.startswith("degraded_reasons="):
        reasons = line.split("=",1)[1].strip()
    return degraded, reasons
  except Exception:
    return 0, ""

def _vsp_finalize_unify_sync_v5(ci_run_dir: str):
  root = _vsp_bundle_root_v5()
  unify = root / "bin" / "vsp_unify_from_run_dir_v1.sh"
  sync  = root / "bin" / "vsp_ci_sync_to_vsp_v1.sh"
  logs = []
  ok = True
  if unify.exists():
    r = _subprocess.run([str(unify), str(ci_run_dir)], capture_output=True, text=True)
    logs.append(f"[UNIFY rc={r.returncode}]")
    if r.returncode != 0:
      ok = False
      logs.append((r.stdout or "")[-2000:])
      logs.append((r.stderr or "")[-2000:])
  else:
    ok = False
    logs.append("[UNIFY missing]")
  if sync.exists():
    r2 = _subprocess.run([str(sync), str(ci_run_dir)], capture_output=True, text=True)
    logs.append(f"[SYNC rc={r2.returncode}]")
    if r2.returncode != 0:
      ok = False
      logs.append((r2.stdout or "")[-2000:])
      logs.append((r2.stderr or "")[-2000:])
  else:
    ok = False
    logs.append("[SYNC missing]")
  return ok, "\n".join([x for x in logs if x])
# === END VSP_WATCHDOG_KILL_FINALIZE_V5 ===
'''
txt = txt.rstrip() + "\n" + helpers + "\n"

# 2) Ensure run_v1 stores pid/setsid (best-effort string inject)
# Add preexec_fn=os.setsid if subprocess.Popen exists and not already setsid
if "preexec_fn=os.setsid" not in txt and "subprocess.Popen" in txt and "os.setsid" in txt:
  txt = txt.replace("subprocess.Popen(", "subprocess.Popen(", 1)  # no-op; keep

# Inject pid save after `proc = subprocess.Popen(...)` (or similar)
m = re.search(r"(?m)^\s*(\w+)\s*=\s*subprocess\.Popen\(", txt)
if m:
  proc_var = m.group(1)
  # find end of that statement block by next blank line (coarse) and inject after it once
  idx = m.start()
  nl = txt.find("\n", idx)
  inject_after = nl
  if inject_after != -1 and "VSP_RUNV1_SAVE_PID_V5" not in txt:
    ins = f"""
    # === VSP_RUNV1_SAVE_PID_V5 ===
    try:
      import os, time
      st = _vsp_load_state_v5(req_id)
      st.setdefault("watch", {{}})
      st["pid"] = int(getattr({proc_var}, "pid", 0) or 0)
      st["status"] = "RUNNING"
      st["final"] = False
      now = time.time()
      st["watch"].setdefault("start_ts", now)
      st["watch"].setdefault("last_stage_at", now)
      st["watch"].setdefault("last_stage_sig", "")
      st["watch"]["stall_timeout_sec"] = int(os.environ.get("VSP_UIREQ_STALL_TIMEOUT_SEC", "600"))
      st["watch"]["total_timeout_sec"] = int(os.environ.get("VSP_UIREQ_TOTAL_TIMEOUT_SEC", "7200"))
      _vsp_save_state_v5(req_id, st)
    except Exception:
      pass
    # === END VSP_RUNV1_SAVE_PID_V5 ===
"""
    # inject after the line that starts proc assignment (safe minimal)
    txt = txt[:inject_after+1] + ins + txt[inject_after+1:]
else:
  print("[WARN] cannot find 'proc = subprocess.Popen(' pattern; skip pid-save injection (watchdog may not kill)")

# 3) Inject watchdog+finalize into status handler (we key off stage_index/progress_pct presence)
needle = "st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding=\"utf-8\")"
if needle in txt and "VSP_STATUS_WATCHDOG_BLOCK_V5" not in txt:
  inject = r'''
  # === VSP_STATUS_WATCHDOG_BLOCK_V5 ===
  try:
    now = _time.time()
    st.setdefault("watch", {})
    watch = st.get("watch") or {}
    st["watch"] = watch

    # update stage signature
    sig = f"{st.get('stage_index',0)}/{st.get('stage_total',0)}:{st.get('stage_name','')}"
    if sig and sig != watch.get("last_stage_sig", ""):
      watch["last_stage_sig"] = sig
      watch["last_stage_at"] = now

    # watchdog only when RUNNING and not final
    status_u = str(st.get("status","")).upper()
    if status_u == "RUNNING" and not bool(st.get("final")):
      stall = int(_os.environ.get("VSP_UIREQ_STALL_TIMEOUT_SEC", str(watch.get("stall_timeout_sec", 600))))
      total = int(_os.environ.get("VSP_UIREQ_TOTAL_TIMEOUT_SEC", str(watch.get("total_timeout_sec", 7200))))
      start_ts = float(watch.get("start_ts", now))
      last_stage_at = float(watch.get("last_stage_at", start_ts))
      pid = int(st.get("pid", 0) or 0)

      if total > 0 and (now - start_ts) > total:
        st["status"] = "TIMEOUT"
        st["final"] = True
        if pid:
          ok, how = _vsp_kill_pgid_v5(pid)
          st["killed"] = ok
          st["kill_reason"] = how

      elif stall > 0 and (now - last_stage_at) > stall:
        st["status"] = "STALLED"
        st["final"] = True
        if pid:
          ok, how = _vsp_kill_pgid_v5(pid)
          st["killed"] = ok
          st["kill_reason"] = how

    # finalize unify+sync once when final
    if bool(st.get("final")) and st.get("ci_run_dir"):
      sync = st.get("sync") or {"done": False, "ok": None, "msg": ""}
      if not bool(sync.get("done")):
        ok, msg = _vsp_finalize_unify_sync_v5(st["ci_run_dir"])
        sync["done"] = True
        sync["ok"] = bool(ok)
        sync["msg"] = msg
      st["sync"] = sync

      d, reasons = _vsp_read_degraded_v5(st["ci_run_dir"])
      st["degraded"] = int(d)
      st["degraded_reasons"] = reasons
      if d and str(st.get("status","")).upper() in ("DONE","OK","SUCCESS"):
        st["status"] = "DEGRADED"
  except Exception as _e:
    st.setdefault("sync", {"done": False, "ok": None, "msg": ""})
    st["sync"]["msg"] = (st["sync"].get("msg","") + "\n" + str(_e)).strip()
  # === END VSP_STATUS_WATCHDOG_BLOCK_V5 ===
'''
  txt = txt.replace(needle, inject + "\n  " + needle, 1)
else:
  if needle not in txt:
    print("[ERR] cannot find persistence needle; file layout unexpected")
    raise SystemExit(2)

p.write_text(txt, encoding="utf-8")
print("[OK] watchdog+finalize injected")
PY

python3 -m py_compile "$PYF"
echo "[OK] py_compile OK"
echo "[DONE]"
