#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_uireq_persist_${TS}"
echo "[BACKUP] $F.bak_uireq_persist_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_UIREQ_PERSIST_AND_RESOLVE_CI_V1 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Find run_status_v1 handler by route or function name
route_m = re.search(r'(?m)^\s*@.*route\(\s*[\'"][^\'"]*run_status_v1[^\'"]*[\'"]', t)
start = None
if route_m:
    mdef = re.search(r'(?m)^\s*def\s+\w+\s*\(', t[route_m.start():])
    if mdef:
        start = route_m.start() + mdef.start()
if start is None:
    m = re.search(r'(?m)^\s*def\s+\w*run_status_v1\w*\s*\(', t)
    if m:
        start = m.start()
if start is None:
    print("[ERR] cannot find run_status_v1 handler")
    raise SystemExit(2)

# Determine handler region end
tail = t[start:]
m_end = re.search(r'(?m)^(?:@|def)\s+', tail[1:])
end = start + (m_end.start()+1 if m_end else len(t))
region = t[start:end]

# Insert before last jsonify return inside handler
rets = list(re.finditer(r'(?m)^\s*return\s+.*jsonify\s*\(.*$', region))
if not rets:
    print("[ERR] cannot find jsonify return in run_status_v1 handler")
    raise SystemExit(3)

last_ret = rets[-1]
ins_at = start + last_ret.start()
ret_line = region[last_ret.start():region.find("\n", last_ret.start())]
indent = re.match(r'^(\s*)', ret_line).group(1)

block = f"""{indent}{TAG}
{indent}# Persist UIREQ state under out_ci/uireq_v1 and try resolve ci_run_dir from state (commercial)
{indent}try:
{indent}    import os, json, glob, datetime
{indent}    rid = req_id if 'req_id' in locals() else (request_id if 'request_id' in locals() else None)
{indent}    if not rid:
{indent}        rid = (locals().get("REQ_ID") or locals().get("RID") or None)
{indent}    udir = os.path.join(os.path.dirname(__file__), "out_ci", "uireq_v1")
{indent}    os.makedirs(udir, exist_ok=True)
{indent}    spath = os.path.join(udir, f"{{rid}}.json") if rid else None
{indent}
{indent}    # choose dst dict (prefer resp/out)
{indent}    dst = None
{indent}    if isinstance(locals().get("resp", None), dict): dst = resp
{indent}    if isinstance(locals().get("out", None), dict): dst = out
{indent}
{indent}    if isinstance(dst, dict):
{indent}        # normalize empties
{indent}        if dst.get("stage_name") is None: dst["stage_name"] = ""
{indent}        if dst.get("ci_run_dir") is None: dst["ci_run_dir"] = ""
{indent}
{indent}        # resolve ci_run_dir if empty: read previously persisted state or fallback to latest CI dir
{indent}        if (not dst.get("ci_run_dir")) and spath and os.path.isfile(spath):
{indent}            try:
{indent}                j = json.load(open(spath, "r", encoding="utf-8"))
{indent}                dst["ci_run_dir"] = j.get("ci_run_dir") or j.get("ci") or dst.get("ci_run_dir") or ""
{indent}            except Exception:
{indent}                pass
{indent}
{indent}        if (not dst.get("ci_run_dir")):
{indent}            # fallback guess: newest CI dir under /home/test/Data/SECURITY-10-10-v4/out_ci
{indent}            cand = sorted(glob.glob("/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_*"), reverse=True)
{indent}            if cand:
{indent}                dst["ci_run_dir"] = cand[0]
{indent}
{indent}        # persist state every call (so UI has stable mapping)
{indent}        if spath:
{indent}            payload = dict(dst)
{indent}            payload["ts_persist"] = datetime.datetime.utcnow().isoformat() + "Z"
{indent}            try:
{indent}                open(spath, "w", encoding="utf-8").write(json.dumps(payload, ensure_ascii=False, indent=2))
{indent}            except Exception:
{indent}                pass
{indent}except Exception:
{indent}    pass
"""

t2 = t[:ins_at] + block + "\n" + t[ins_at:]
p.write_text(t2, encoding="utf-8")
print("[OK] patched run_status_v1: persist+resolve uireq_v1")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

if [ -x bin/restart_8910_gunicorn_commercial_v5.sh ]; then
  bin/restart_8910_gunicorn_commercial_v5.sh
else
  echo "[WARN] missing restart script; restart 8910 manually"
fi

echo "== VERIFY =="
RID="$(ls -1 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1 2>/dev/null | sed 's/\.json$//' | tail -n 1 || true)"
echo "RID(last)=$RID"
[ -n "$RID" ] && curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v1/$RID" | jq '{ok, stage_name, pct, ci_run_dir}'
