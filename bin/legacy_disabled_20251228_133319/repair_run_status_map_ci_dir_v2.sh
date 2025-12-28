#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_map_ci_v2_${TS}"
echo "[BACKUP] $F.bak_map_ci_v2_${TS}"

python3 - <<'PY'
import re, json
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# 1) remove old V1 block if present
txt2, n = re.subn(
    r"\n?[ \t]*# VSP_RUN_STATUS_MAP_CI_DIR_V1[\s\S]*?[ \t]*# END VSP_RUN_STATUS_MAP_CI_DIR_V1\n?",
    "\n",
    txt,
    flags=re.M
)
if n:
    print("[FIX] removed V1 block count=", n)
else:
    print("[INFO] no V1 block found (ok)")

MARK = "VSP_RUN_STATUS_MAP_CI_DIR_V2"
if MARK in txt2:
    print("[OK] already patched:", MARK)
    p.write_text(txt2, encoding="utf-8")
    raise SystemExit(0)

# 2) locate run_status_v1(req_id) and its 'return jsonify(st)' to inject before return
m_fn = re.search(r"^def\s+run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", txt2, flags=re.M)
if not m_fn:
    raise SystemExit("[ERR] cannot find def run_status_v1(req_id):")

m_next = re.search(r"^def\s+\w+\s*\(", txt2[m_fn.end():], flags=re.M)
fn_end = len(txt2) if not m_next else (m_fn.end() + m_next.start())
fn = txt2[m_fn.start():fn_end]

m_ret = None
for mm in re.finditer(r"^[ \t]*return\s+jsonify\s*\(\s*st\s*\)\s*(?:,\s*\d+\s*)?$", fn, flags=re.M):
    m_ret = mm
if not m_ret:
    raise SystemExit("[ERR] cannot find 'return jsonify(st)' inside run_status_v1()")

indent = re.match(r"[ \t]*", m_ret.group(0)).group(0)

snippet = f"""
{indent}# {MARK}
{indent}try:
{indent}  from pathlib import Path as _P
{indent}  import os as _os, json as _json
{indent}  if isinstance(st, dict):
{indent}    _ci = (st.get("ci_run_dir") or "").strip()
{indent}    _rl = (st.get("runner_log") or "").strip()
{indent}    tgt = (st.get("target") or "").strip()
{indent}    # only attempt mapping when missing
{indent}    if (not _ci) or (not _rl):
{indent}      bases = []
{indent}      if tgt:
{indent}        tp = _P(tgt)
{indent}        bases += [
{indent}          tp / "out_ci",
{indent}          tp / "out_ci" / "VSP_CI_OUTER",
{indent}          tp / "out_ci" / "VSP_CI_OUTER" / "out_ci",
{indent}          tp / "ci" / "VSP_CI_OUTER",
{indent}          tp / "ci" / "VSP_CI_OUTER" / "out_ci",
{indent}        ]
{indent}      # helper: pick newest file/dir
{indent}      def _newest(paths):
{indent}        best = None
{indent}        best_m = -1
{indent}        for x in paths:
{indent}          try:
{indent}            mt = x.stat().st_mtime
{indent}            if mt > best_m:
{indent}              best_m = mt
{indent}              best = x
{indent}          except Exception:
{indent}            pass
{indent}        return best
{indent}      # 1) find newest runner.log (depth-limited)
{indent}      cand_logs = []
{indent}      for b in bases:
{indent}        try:
{indent}          if not b.is_dir(): 
{indent}            continue
{indent}          # depth <= 4
{indent}          for rp in b.glob("*/*/*/runner.log"):
{indent}            if rp.is_file(): cand_logs.append(rp)
{indent}          for rp in b.glob("*/*/runner.log"):
{indent}            if rp.is_file(): cand_logs.append(rp)
{indent}          for rp in b.glob("*/runner.log"):
{indent}            if rp.is_file(): cand_logs.append(rp)
{indent}        except Exception:
{indent}          pass
{indent}      best_log = _newest(cand_logs) if cand_logs else None
{indent}      if best_log:
{indent}        st["runner_log"] = str(best_log)
{indent}        st["ci_run_dir"] = str(best_log.parent)
{indent}        _ci = st["ci_run_dir"]; _rl = st["runner_log"]
{indent}      # 2) else find newest VSP_CI_* dir
{indent}      if not _ci:
{indent}        cand_dirs = []
{indent}        for b in bases:
{indent}          try:
{indent}            if not b.is_dir(): 
{indent}              continue
{indent}            for d in b.iterdir():
{indent}              if d.is_dir() and d.name.startswith("VSP_CI_"):
{indent}                cand_dirs.append(d)
{indent}          except Exception:
{indent}            pass
{indent}        best_dir = _newest(cand_dirs) if cand_dirs else None
{indent}        if best_dir:
{indent}          st["ci_run_dir"] = str(best_dir)
{indent}          _ci = st["ci_run_dir"]
{indent}      # 3) else fallback newest dir under out_ci (any name)
{indent}      if (not _ci) and tgt:
{indent}        try:
{indent}          oc = _P(tgt) / "out_ci"
{indent}          if oc.is_dir():
{indent}            cand_any = [d for d in oc.iterdir() if d.is_dir()]
{indent}            best_any = _newest(cand_any) if cand_any else None
{indent}            if best_any:
{indent}              st["ci_run_dir"] = str(best_any)
{indent}              _ci = st["ci_run_dir"]
{indent}        except Exception:
{indent}          pass
{indent}      # set canonical runner_log path if we have ci dir
{indent}      if _ci and (not _rl):
{indent}        st["runner_log"] = str(_P(_ci) / "runner.log")
{indent}      # persist back to statefile so next polls keep values
{indent}      try:
{indent}        udir = globals().get("_VSP_UIREQ_DIR")
{indent}        if udir and isinstance(udir, _P):
{indent}          sf = udir / f"{{req_id}}.json"
{indent}          if sf.parent.exists():
{indent}            sf.write_text(_json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
{indent}      except Exception:
{indent}        pass
{indent}except Exception:
{indent}  pass
{indent}# END {MARK}
"""

fn2 = fn[:m_ret.start()] + snippet + fn[m_ret.start():]
txt3 = txt2[:m_fn.start()] + fn2 + txt2[fn_end:]

p.write_text(txt3, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
