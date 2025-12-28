#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

# 1) restore from latest bak_watchdog_finalize_*
LATEST_BAK="$(ls -1 "${PYF}.bak_watchdog_finalize_"* 2>/dev/null | sort | tail -n1 || true)"
if [ -z "$LATEST_BAK" ]; then
  echo "[ERR] cannot find backup: ${PYF}.bak_watchdog_finalize_*"
  exit 1
fi

cp "$LATEST_BAK" "$PYF"
echo "[RESTORE] $PYF <= $LATEST_BAK"

# 2) patch run_status_v1 body by inserting block before st_path.write_text(...)
python3 - << 'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_WATCHDOG_FINALIZE_SAFE_V6"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# find the write-back line inside status handler (from AST v3 patch)
m = re.search(r'(?m)^(?P<indent>\s*)st_path\.write_text\(json\.dumps\(st,\s*ensure_ascii=False,\s*indent=2\),\s*encoding="utf-8"\)\s*$', txt)
if not m:
    # fallback: locate any st_path.write_text(json.dumps(st ...))
    m = re.search(r'(?m)^(?P<indent>\s*)st_path\.write_text\(.+json\.dumps\(st.+indent=2\).+\)\s*$', txt)
if not m:
    print("[ERR] cannot find st_path.write_text(json.dumps(st,...)) line to inject before")
    raise SystemExit(2)

indent = m.group("indent")

block = f"""{indent}# === {MARK} ===
{indent}try:
{indent}  import os, time, signal, subprocess
{indent}  now = time.time()
{indent}  st.setdefault("watch", {{}})
{indent}  watch = st.get("watch") or {{}}
{indent}  st["watch"] = watch
{indent}  # stage signature
{indent}  sig = f"{{st.get('stage_index',0)}}/{{st.get('stage_total',0)}}:{{st.get('stage_name','')}}"
{indent}  if sig and sig != watch.get("last_stage_sig",""):
{indent}    watch["last_stage_sig"] = sig
{indent}    watch["last_stage_at"] = now
{indent}  watch.setdefault("start_ts", now)
{indent}  watch.setdefault("last_stage_at", watch.get("start_ts", now))
{indent}  # timeouts
{indent}  stall = int(os.environ.get("VSP_UIREQ_STALL_TIMEOUT_SEC", "600"))
{indent}  total = int(os.environ.get("VSP_UIREQ_TOTAL_TIMEOUT_SEC", "7200"))
{indent}  start_ts = float(watch.get("start_ts") or now)
{indent}  last_stage_at = float(watch.get("last_stage_at") or start_ts)
{indent}  status_u = str(st.get("status","")).upper()
{indent}  # watchdog: if running and not final
{indent}  if status_u == "RUNNING" and not bool(st.get("final")):
{indent}    if total > 0 and (now - start_ts) > total:
{indent}      st["status"] = "TIMEOUT"
{indent}      st["final"] = True
{indent}    elif stall > 0 and (now - last_stage_at) > stall:
{indent}      st["status"] = "STALLED"
{indent}      st["final"] = True
{indent}    # best-effort kill when final triggered
{indent}    if bool(st.get("final")):
{indent}      pid = int(st.get("pid", 0) or 0)
{indent}      # if no pid stored, try find by ci_run_dir in process cmdline
{indent}      if pid == 0 and st.get("ci_run_dir"):
{indent}        try:
{indent}          r = subprocess.run(["pgrep","-f", str(st["ci_run_dir"])], capture_output=True, text=True)
{indent}          out = (r.stdout or "").strip().splitlines()
{indent}          if out:
{indent}            pid = int(out[0].strip())
{indent}        except Exception:
{indent}          pid = 0
{indent}      if pid:
{indent}        try:
{indent}          os.killpg(pid, signal.SIGTERM)
{indent}          st["killed"] = True
{indent}          st["kill_reason"] = "SIGTERM(pgid)"
{indent}        except Exception:
{indent}          try:
{indent}            os.kill(pid, signal.SIGTERM)
{indent}            st["killed"] = True
{indent}            st["kill_reason"] = "SIGTERM(pid)"
{indent}          except Exception as e:
{indent}            st["killed"] = False
{indent}            st["kill_reason"] = f"kill_failed:{{e}}"
{indent}  # finalize unify+sync once when final
{indent}  if bool(st.get("final")) and st.get("ci_run_dir"):
{indent}    sync = st.get("sync") or {{"done": False, "ok": None, "msg": ""}}
{indent}    if not bool(sync.get("done")):
{indent}      bundle_root = Path(__file__).resolve().parents[2]
{indent}      unify = bundle_root / "bin" / "vsp_unify_from_run_dir_v1.sh"
{indent}      syncsh = bundle_root / "bin" / "vsp_ci_sync_to_vsp_v1.sh"
{indent}      logs = []
{indent}      ok = True
{indent}      if unify.exists():
{indent}        rr = subprocess.run([str(unify), str(st["ci_run_dir"])], capture_output=True, text=True)
{indent}        logs.append(f"[UNIFY rc={{rr.returncode}}]")
{indent}        if rr.returncode != 0:
{indent}          ok = False
{indent}          logs.append((rr.stdout or "")[-2000:])
{indent}          logs.append((rr.stderr or "")[-2000:])
{indent}      else:
{indent}        ok = False
{indent}        logs.append("[UNIFY missing]")
{indent}      if syncsh.exists():
{indent}        rr2 = subprocess.run([str(syncsh), str(st["ci_run_dir"])], capture_output=True, text=True)
{indent}        logs.append(f"[SYNC rc={{rr2.returncode}}]")
{indent}        if rr2.returncode != 0:
{indent}          ok = False
{indent}          logs.append((rr2.stdout or "")[-2000:])
{indent}          logs.append((rr2.stderr or "")[-2000:])
{indent}      else:
{indent}        ok = False
{indent}        logs.append("[SYNC missing]")
{indent}      sync["done"] = True
{indent}      sync["ok"] = bool(ok)
{indent}      sync["msg"] = "\\n".join([x for x in logs if x])
{indent}    st["sync"] = sync
{indent}    # degraded env (optional)
{indent}    try:
{indent}      f = Path(st["ci_run_dir"]) / "vsp_degraded.env"
{indent}      if not f.exists():
{indent}        f = Path(st["ci_run_dir"]) / "out" / "vsp_degraded.env"
{indent}      if f.exists():
{indent}        degraded = 0
{indent}        reasons = ""
{indent}        for line in f.read_text(encoding="utf-8", errors="ignore").splitlines():
{indent}          if line.startswith("degraded="):
{indent}            try: degraded = int(line.split("=",1)[1].strip() or "0")
{indent}            except: degraded = 0
{indent}          if line.startswith("degraded_reasons="):
{indent}            reasons = line.split("=",1)[1].strip()
{indent}        st["degraded"] = int(degraded)
{indent}        st["degraded_reasons"] = reasons
{indent}    except Exception:
{indent}      pass
{indent}except Exception as _e:
{indent}  st.setdefault("sync", {{"done": False, "ok": None, "msg": ""}})
{indent}  st["sync"]["msg"] = (st["sync"].get("msg","") + "\\n" + str(_e)).strip()
{indent}# === END {MARK} ===
"""

# inject block just before the write_text line
pos = m.start()
txt2 = txt[:pos] + block + "\n" + txt[pos:]
p.write_text(txt2, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$PYF"
echo "[OK] py_compile OK"
echo "[DONE]"
