#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_finalize_${TS}"
echo "[BACKUP] $PYF.bak_finalize_${TS}"

python3 - << 'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_FINALIZE_UNIFY_SYNC_V4"
if MARK in txt:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert helper functions once
helper = r'''
# === VSP_FINALIZE_UNIFY_SYNC_V4 ===
def _vsp_read_degraded_env(ci_run_dir: str):
  try:
    from pathlib import Path
    f = Path(ci_run_dir) / "vsp_degraded.env"
    if not f.exists():
      f = Path(ci_run_dir) / "out" / "vsp_degraded.env"
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

def _vsp_finalize_unify_sync(ci_run_dir: str):
  import subprocess
  from pathlib import Path
  bundle_root = Path(__file__).resolve().parents[2]  # .../SECURITY_BUNDLE
  unify = bundle_root / "bin" / "vsp_unify_from_run_dir_v1.sh"
  sync  = bundle_root / "bin" / "vsp_ci_sync_to_vsp_v1.sh"
  logs = []
  ok = True
  if unify.exists():
    r = subprocess.run([str(unify), str(ci_run_dir)], capture_output=True, text=True)
    logs.append(f"[UNIFY rc={r.returncode}]")
    if r.returncode != 0:
      ok = False
      logs.append((r.stdout or "")[-2000:])
      logs.append((r.stderr or "")[-2000:])
  else:
    ok = False
    logs.append("[UNIFY missing]")
  if sync.exists():
    r2 = subprocess.run([str(sync), str(ci_run_dir)], capture_output=True, text=True)
    logs.append(f"[SYNC rc={r2.returncode}]")
    if r2.returncode != 0:
      ok = False
      logs.append((r2.stdout or "")[-2000:])
      logs.append((r2.stderr or "")[-2000:])
  else:
    ok = False
    logs.append("[SYNC missing]")
  return ok, "\n".join([x for x in logs if x])
# === END VSP_FINALIZE_UNIFY_SYNC_V4 ===
'''
txt = txt.rstrip() + "\n" + helper + "\n"

# Patch inside run_status_v1 handler (the AST v3 block contains: st_path.write_text(...); return jsonify(st))
# We inject finalize just before persisting.
needle = "st_path.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding=\"utf-8\")"
if needle not in txt:
    print("[ERR] cannot find persistence needle in run_status handler (unexpected file layout)")
    raise SystemExit(2)

inject = r'''
  # commercial finalize: unify + sync once when final
  try:
    if bool(st.get("final")) and st.get("ci_run_dir"):
      sync = st.get("sync") or {"done": False, "ok": None, "msg": ""}
      if not bool(sync.get("done")):
        ok, msg = _vsp_finalize_unify_sync(st["ci_run_dir"])
        sync["done"] = True
        sync["ok"] = bool(ok)
        sync["msg"] = msg
      st["sync"] = sync

      d, reasons = _vsp_read_degraded_env(st["ci_run_dir"])
      st["degraded"] = int(d)
      st["degraded_reasons"] = reasons
      if d and st.get("status","").upper() in ("DONE","OK","SUCCESS"):
        st["status"] = "DEGRADED"
  except Exception as _e:
    # do not break status endpoint
    st["sync"] = st.get("sync") or {"done": False, "ok": None, "msg": ""}
    st["sync"]["msg"] = (st["sync"].get("msg","") + "\n" + str(_e)).strip()
'''

txt = txt.replace(needle, inject + "\n  " + needle, 1)
p.write_text(txt, encoding="utf-8")
print("[OK] injected finalize unify+sync into run_status handler")
PY

python3 -m py_compile "$PYF"
echo "[OK] py_compile OK"
echo "[DONE]"
