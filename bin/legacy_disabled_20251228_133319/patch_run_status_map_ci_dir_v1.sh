#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_map_ci_${TS}"
echo "[BACKUP] $F.bak_map_ci_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_STATUS_MAP_CI_DIR_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

m_fn = re.search(r"^def\s+run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", txt, flags=re.M)
if not m_fn:
    raise SystemExit("[ERR] cannot find def run_status_v1(req_id):")

m_next = re.search(r"^def\s+\w+\s*\(", txt[m_fn.end():], flags=re.M)
fn_end = len(txt) if not m_next else (m_fn.end() + m_next.start())
fn = txt[m_fn.start():fn_end]

# find "return jsonify(st)" inside function
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
{indent}  # only fill if missing
{indent}  if isinstance(st, dict):
{indent}    _ci = st.get("ci_run_dir") or ""
{indent}    _rl = st.get("runner_log") or ""
{indent}    if (not _ci) or (not _rl):
{indent}      tgt = (st.get("target") or "").strip()
{indent}      bases = []
{indent}      if tgt:
{indent}        tp = _P(tgt)
{indent}        bases += [tp / "out_ci", tp / "ci" / "VSP_CI_OUTER", tp / "ci" / "VSP_CI_OUTER" / "out"]
{indent}      # pick newest VSP_CI_* dir
{indent}      best = None
{indent}      best_m = -1
{indent}      for b in bases:
{indent}        try:
{indent}          if not b.is_dir(): 
{indent}            continue
{indent}          for d in b.iterdir():
{indent}            if d.is_dir() and d.name.startswith("VSP_CI_"):
{indent}              mt = d.stat().st_mtime
{indent}              if mt > best_m:
{indent}                best_m = mt
{indent}                best = d
{indent}        except Exception:
{indent}          pass
{indent}      if best and (not _ci):
{indent}        st["ci_run_dir"] = str(best)
{indent}        _ci = st["ci_run_dir"]
{indent}      if _ci and (not _rl):
{indent}        rp = _P(_ci) / "runner.log"
{indent}        if rp.is_file():
{indent}          st["runner_log"] = str(rp)
{indent}        else:
{indent}          # still set canonical path for parser to wait on
{indent}          st["runner_log"] = str(rp)
{indent}except Exception:
{indent}  pass
{indent}# END {MARK}
"""

fn2 = fn[:m_ret.start()] + snippet + fn[m_ret.start():]
txt2 = txt[:m_fn.start()] + fn2 + txt[fn_end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
