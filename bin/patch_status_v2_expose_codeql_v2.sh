#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_codeql_statusv2_v2_${TS}"
echo "[BACKUP] $F.bak_codeql_statusv2_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_STATUSV2_EXPOSE_CODEQL_V2 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

# 1) Find run_status_v2 handler region
# Prefer: decorator with run_status_v2 route
route_m = re.search(r'(?m)^\s*@.*route\(\s*[\'"][^\'"]*run_status_v2[^\'"]*[\'"]', t)
def_m = None
start = None

if route_m:
    # from decorator, find next def
    def_m = re.search(r'(?m)^\s*def\s+\w+\s*\(', t[route_m.start():])
    if def_m:
        start = route_m.start() + def_m.start()
else:
    # fallback: function name contains run_status_v2
    m = re.search(r'(?m)^\s*def\s+\w*run_status_v2\w*\s*\(', t)
    if m:
        start = m.start()

if start is None:
    print("[ERR] cannot find run_status_v2 handler (no route/def match)")
    raise SystemExit(2)

# 2) Determine end of handler as next top-level decorator/def (best-effort)
tail = t[start:]
m_end = re.search(r'(?m)^(?:@|def)\s+', tail[1:])  # next block start
end = start + (m_end.start()+1 if m_end else len(t))

region = t[start:end]

# 3) Find last "return ... jsonify(...)" inside region
rets = list(re.finditer(r'(?m)^\s*return\s+.*jsonify\s*\(.*$', region))
if not rets:
    print("[ERR] cannot find 'return ... jsonify(...)' inside run_status_v2 handler")
    raise SystemExit(3)

last_ret = rets[-1]
ins_at = start + last_ret.start()

# Determine indentation from return line
ret_line = region[last_ret.start():region.find("\n", last_ret.start())]
indent = re.match(r'^(\s*)', ret_line).group(1)

block = f"""{indent}{TAG}
{indent}# Expose CodeQL fields for UI binding (no-null)
{indent}try:
{indent}    import os, json
{indent}    _ci = None
{indent}    # Prefer ci_run_dir from out-dict if available
{indent}    if isinstance(locals().get("out", None), dict):
{indent}        _ci = out.get("ci_run_dir") or out.get("ci") or out.get("run_dir")
{indent}    if (not _ci) and ("ci_run_dir" in locals()):
{indent}        _ci = locals().get("ci_run_dir")
{indent}    if isinstance(locals().get("resp", None), dict) and (not _ci):
{indent}        _ci = resp.get("ci_run_dir") or resp.get("ci") or resp.get("run_dir")
{indent}
{indent}    # Pick target dict to enrich (prefer 'out', else 'resp')
{indent}    _dst = out if isinstance(locals().get("out", None), dict) else (resp if isinstance(locals().get("resp", None), dict) else None)
{indent}    if isinstance(_dst, dict):
{indent}        _dst.setdefault("has_codeql", False)
{indent}        _dst.setdefault("codeql_verdict", None)
{indent}        _dst.setdefault("codeql_total", 0)
{indent}
{indent}        codeql_dir = os.path.join(_ci, "codeql") if _ci else None
{indent}        if codeql_dir and os.path.isdir(codeql_dir):
{indent}            summary = os.path.join(codeql_dir, "codeql_summary.json")
{indent}            if os.path.isfile(summary):
{indent}                try:
{indent}                    j = json.load(open(summary, "r", encoding="utf-8"))
{indent}                except Exception:
{indent}                    j = {{}}
{indent}                _dst["has_codeql"] = True
{indent}                _dst["codeql_verdict"] = j.get("verdict") or j.get("overall_verdict") or "AMBER"
{indent}                try:
{indent}                    _dst["codeql_total"] = int(j.get("total") or 0)
{indent}                except Exception:
{indent}                    _dst["codeql_total"] = 0
{indent}            else:
{indent}                sarifs = [x for x in os.listdir(codeql_dir) if x.lower().endswith(".sarif")]
{indent}                if sarifs:
{indent}                    _dst["has_codeql"] = True
{indent}                    _dst["codeql_verdict"] = _dst.get("codeql_verdict") or "AMBER"
{indent}except Exception:
{indent}    pass
"""

t2 = t[:ins_at] + block + "\n" + t[ins_at:]
p.write_text(t2, encoding="utf-8")
print("[OK] patched status_v2 handler: inserted before last jsonify-return")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

if [ -x bin/restart_8910_gunicorn_commercial_v5.sh ]; then
  bin/restart_8910_gunicorn_commercial_v5.sh
else
  echo "[WARN] missing restart script; restart 8910 manually"
fi

echo "== VERIFY =="
CI="$(ls -1dt /home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_* 2>/dev/null | head -n 1)"
RID="RUN_$(basename "$CI")"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq '{ok, has_codeql, codeql_verdict, codeql_total, has_gitleaks, gitleaks_total, overall_verdict}'
