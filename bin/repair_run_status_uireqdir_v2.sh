#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_repair_uireqdir_${TS}"
echo "[BACKUP] $F.bak_repair_uireqdir_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# 1) remove broken V1 block (between markers)
start = r"# === VSP_RUN_STATUS_READ_UIREQDIR_V1 ==="
end   = r"# === END VSP_RUN_STATUS_READ_UIREQDIR_V1 ==="
pat = re.compile(rf"\n[ \t]*{re.escape(start)}[\s\S]*?{re.escape(end)}[ \t]*\n", re.M)

txt2, n = pat.subn("\n", txt)
if n:
    print(f"[FIX] removed V1 block count={n}")
else:
    print("[FIX] no V1 block found (ok)")

# 2) inject V2 safe fallback right before 'return jsonify(st)' inside run_status_v1
MARK = "VSP_RUN_STATUS_READ_UIREQDIR_V2_SAFE"
if MARK in txt2:
    print("[OK] already has V2 marker:", MARK)
    p.write_text(txt2, encoding="utf-8")
    raise SystemExit(0)

m_fn = re.search(r"^def\s+run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", txt2, flags=re.M)
if not m_fn:
    raise SystemExit("[ERR] cannot find def run_status_v1(req_id):")

m_next = re.search(r"^def\s+\w+\s*\(", txt2[m_fn.end():], flags=re.M)
fn_end = len(txt2) if not m_next else (m_fn.end() + m_next.start())
fn = txt2[m_fn.start():fn_end]

# find the return jsonify(st) line inside this function
m_ret = None
for mm in re.finditer(r"^[ \t]*return\s+jsonify\s*\(\s*st\s*\)\s*(?:,\s*\d+\s*)?$", fn, flags=re.M):
    m_ret = mm
if not m_ret:
    raise SystemExit("[ERR] cannot find 'return jsonify(st)' inside run_status_v1()")

indent = re.match(r"[ \t]*", m_ret.group(0)).group(0)

snippet = f"""\n{indent}# {MARK}\n{indent}# Fallback: if primary state is empty/partial, read from _VSP_UIREQ_DIR/<req_id>.json (where run_v1 bootstrap writes)\n{indent}try:\n{indent}    if (not isinstance(st, dict)) or (not st) or (not (st.get("request_id") or st.get("req_id"))):\n{indent}        try:\n{indent}            f2 = _VSP_UIREQ_DIR / f"{{req_id}}.json"\n{indent}        except Exception:\n{indent}            from pathlib import Path as _P\n{indent}            f2 = _P(__file__).resolve().parents[1] / "ui" / "out_ci" / "uireq_v1" / f"{{req_id}}.json"\n{indent}        if f2 and getattr(f2, "is_file", lambda: False)():\n{indent}            import json as _json\n{indent}            st = _json.loads(f2.read_text(encoding="utf-8", errors="replace"))\n{indent}    if isinstance(st, dict):\n{indent}        st.setdefault("ok", True)\n{indent}        st.setdefault("req_id", str(req_id))\n{indent}        st.setdefault("request_id", st.get("request_id") or str(req_id))\n{indent}except Exception:\n{indent}    pass\n{indent}# END {MARK}\n"""

# insert snippet just before return line
insert_at = m_ret.start()
fn2 = fn[:insert_at] + snippet + fn[insert_at:]

txt3 = txt2[:m_fn.start()] + fn2 + txt2[fn_end:]
p.write_text(txt3, encoding="utf-8")
print("[OK] injected V2 safe block")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
