#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_map_ci_v3_${TS}"
echo "[BACKUP] $F.bak_map_ci_v3_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Remove previous blocks V1/V2 if exist
txt2 = txt
for ver in ["VSP_RUN_STATUS_MAP_CI_DIR_V1", "VSP_RUN_STATUS_MAP_CI_DIR_V2"]:
    pat = rf"\n?[ \t]*# {ver}[\s\S]*?[ \t]*# END {ver}\n?"
    txt2, n = re.subn(pat, "\n", txt2, flags=re.M)
    if n:
        print("[FIX] removed", ver, "count=", n)

MARK = "VSP_RUN_STATUS_MAP_CI_DIR_V3_DEBUG"
if MARK in txt2:
    print("[OK] already patched:", MARK)
    p.write_text(txt2, encoding="utf-8")
    raise SystemExit(0)

# Find run_status_v1(req_id)
m_fn = re.search(r"^def\s+run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", txt2, flags=re.M)
if not m_fn:
    raise SystemExit("[ERR] cannot find def run_status_v1(req_id):")

m_next = re.search(r"^def\s+\w+\s*\(", txt2[m_fn.end():], flags=re.M)
fn_end = len(txt2) if not m_next else (m_fn.end() + m_next.start())
fn = txt2[m_fn.start():fn_end]

# Find the LAST "return jsonify(st)" inside run_status_v1 (safer)
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
{indent}  import json as _json, re as _re
{indent}  if isinstance(st, dict):
{indent}    _ci = (st.get("ci_run_dir") or "").strip()
{indent}    _rl = (st.get("runner_log") or "").strip()
{indent}    tgt = (st.get("target") or "").strip()
{indent}    rid = (st.get("req_id") or st.get("request_id") or req_id or "").strip()
{indent}    if (not _ci) or (not _rl):
{indent}      best_dir = None
{indent}      best_diff = 10**18
{indent}      cand = []
{indent}      if tgt:
{indent}        oc = _P(tgt) / "out_ci"
{indent}        # parse rid time: VSP_UIREQ_YYYYmmdd_HHMMSS_xxxxxx
{indent}        m = _re.search(r"VSP_UIREQ_(\\d{{8}})_(\\d{{6}})_", rid)
{indent}        rid_key = None
{indent}        if m:
{indent}          rid_key = m.group(1) + m.group(2)  # yyyymmddhhmmss
{indent}        def _to_int(s):
{indent}          try: return int(s)
{indent}          except Exception: return None
{indent}        rid_int = _to_int(rid_key) if rid_key else None
{indent}        if oc.is_dir():
{indent}          for d in oc.iterdir():
{indent}            if not d.is_dir(): 
{indent}              continue
{indent}            # accept VSP_CI_YYYYmmdd_HHMMSS
{indent}            mm = _re.search(r"VSP_CI_(\\d{{8}})_(\\d{{6}})", d.name)
{indent}            if mm:
{indent}              k = mm.group(1) + mm.group(2)
{indent}              di = _to_int(k)
{indent}              cand.append((d, di))
{indent}          # choose nearest by timestamp if possible
{indent}          if rid_int is not None:
{indent}            for d, di in cand:
{indent}              if di is None: 
{indent}                continue
{indent}              diff = abs(di - rid_int)
{indent}              if diff < best_diff:
{indent}                best_diff = diff
{indent}                best_dir = d
{indent}          # fallback newest mtime
{indent}          if best_dir is None and cand:
{indent}            try:
{indent}              best_dir = max([d for d,_ in cand], key=lambda x: x.stat().st_mtime)
{indent}            except Exception:
{indent}              best_dir = None
{indent}      if best_dir:
{indent}        st["ci_run_dir"] = str(best_dir)
{indent}        rp = best_dir / "runner.log"
{indent}        st["runner_log"] = str(rp)
{indent}        try:
{indent}          print("[{MARK}] mapped rid=", rid, "->", str(best_dir), "best_diff=", best_diff, "runner_log_exists=", rp.is_file())
{indent}        except Exception:
{indent}          pass
{indent}      else:
{indent}        try:
{indent}          print("[{MARK}] no ci dir found for rid=", rid, "tgt=", tgt)
{indent}        except Exception:
{indent}          pass
{indent}      # persist back to statefile (uireq dir)
{indent}      try:
{indent}        udir = globals().get("_VSP_UIREQ_DIR")
{indent}        if udir:
{indent}          sf = _P(str(udir)) / f"{{req_id}}.json"
{indent}          sf.parent.mkdir(parents=True, exist_ok=True)
{indent}          sf.write_text(_json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
{indent}      except Exception as e:
{indent}        try: print("[{MARK}] persist failed:", e)
{indent}        except Exception: pass
{indent}except Exception as e:
{indent}  try: print("[{MARK}] exception:", e)
{indent}  except Exception: pass
{indent}# END {MARK}
"""

fn2 = fn[:m_ret.start()] + snippet + fn[m_ret.start():]
out = txt2[:m_fn.start()] + fn2 + txt2[fn_end:]
p.write_text(out, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
