#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_autolink_ci_${TS}"
echo "[BACKUP] $F.bak_autolink_ci_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUN_STATUS_AUTOLINK_CI_DIR_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

m = re.search(r"(?m)^(?P<dindent>[ \t]*)def\s+run_status_v1\s*\(", txt)
if not m:
    raise SystemExit("[ERR] cannot find def run_status_v1(")

dindent = m.group("dindent")
start = m.start()

m2 = re.search(r"(?m)^" + re.escape(dindent) + r"def\s+\w+\s*\(", txt[m.end():])
end = (m.end() + m2.start()) if m2 else len(txt)

fn = txt[start:end]

# find the LAST 'return jsonify(st)' within run_status_v1
ret_iter = list(re.finditer(r"(?m)^[ \t]*return\s+jsonify\s*\(\s*st\s*\)\s*$", fn))
if not ret_iter:
    raise SystemExit("[ERR] cannot find 'return jsonify(st)' inside run_status_v1()")
ret = ret_iter[-1]

# indentation for block: assume 2-space inside function (but keep exactly what file uses)
# We'll detect indent from the return line itself
ret_line = fn[ret.start():ret.end()]
indent = re.match(r"^([ \t]*)return", ret_line).group(1)

i1 = indent
i2 = indent + "  "
i3 = indent + "    "

inject = f"""{i1}# {MARK}
{i1}try:
{i2}# If backend created CI run under target/out_ci/VSP_CI_*/runner.log, link it once.
{i2}_req_id = st.get("req_id") or st.get("request_id") or req_id
{i2}_target = st.get("target") or ""
{i2}if (not st.get("ci_run_dir")) and _target:
{i3}_P = __import__('pathlib').Path
{i3}_json = __import__('json')
{i3}_dt = __import__('datetime')
{i3}_re = __import__('re')
{i3}_os = __import__('os')
{i3}tpath = _P(str(_target))
{i3}out_ci = tpath / "out_ci"
{i3}req_epoch = None
{i3}try:
{i3}  mm = _re.search(r"(?:^|_)VSP_UIREQ_(\\d{{8}})_(\\d{{6}})_", str(_req_id))
{i3}  if mm:
{i3}    ts = mm.group(1) + mm.group(2)  # yyyymmddHHMMSS
{i3}    req_epoch = _dt.datetime.strptime(ts, "%Y%m%d%H%M%S").timestamp()
{i3}except Exception:
{i3}  req_epoch = None
{i3}
{i3}if out_ci.is_dir():
{i3}  cands = []
{i3}  for d in out_ci.iterdir():
{i3}    if not d.is_dir():
{i3}      continue
{i3}    if not d.name.startswith("VSP_CI_"):
{i3}      continue
{i3}    rl = d / "runner.log"
{i3}    try:
{i3}      mt = rl.stat().st_mtime if rl.exists() else d.stat().st_mtime
{i3}    except Exception:
{i3}      mt = 0.0
{i3}    # filter old runs: accept only near req time if available
{i3}    if req_epoch is not None and mt and mt < (req_epoch - 120):
{i3}      continue
{i3}    cands.append((mt, str(d), str(rl) if rl.exists() else None))
{i3}  if cands:
{i3}    cands.sort(key=lambda x: x[0], reverse=True)
{i3}    _mt, best_dir, best_rl = cands[0]
{i3}    st["ci_run_dir"] = best_dir
{i3}    st["runner_log"] = best_rl or str(_P(best_dir) / "runner.log")
{i3}    # persist back to uireq state file
{i3}    try:
{i3}      udir = _P(_VSP_UIREQ_DIR)
{i3}      sp = udir / f"{{_req_id}}.json"
{i3}      if sp.exists():
{i3}        cur = _json.loads(sp.read_text(encoding="utf-8", errors="replace"))
{i3}      else:
{i3}        cur = {{}}
{i3}      cur["ci_run_dir"] = st.get("ci_run_dir")
{i3}      cur["runner_log"] = st.get("runner_log")
{i3}      sp.write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
{i3}    except Exception as _pe:
{i3}      pass
{i3}    try:
{i3}      print("[{MARK}] linked", st.get("ci_run_dir"), "runner_log=", st.get("runner_log"))
{i3}    except Exception:
{i3}      pass
{i1}except Exception as _e:
{i2}try:
{i3}print("[{MARK}] WARN", _e)
{i2}except Exception:
{i3}pass

"""

fn2 = fn[:ret.start()] + inject + fn[ret.start():]
txt2 = txt[:start] + fn2 + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
