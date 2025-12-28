#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_contractize_v3_${TS}"
echo "[OK] backup: ${APP}.bak_contractize_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

helper_tag = "VSP_CONTRACTIZE_V3_V1"
if helper_tag not in s:
    # Add helper near top (after imports) in a safe way
    m = re.search(r"(?m)^(from\s+flask\s+import\s+.*|import\s+flask\b.*)$", s)
    insert_at = m.end() if m else 0
    helper = f"""

# ===== {helper_tag} (commercial: prevent UI infinite loading) =====
def _vsp_norm_sev(d=None):
    d = d if isinstance(d, dict) else {{}}
    for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
        d.setdefault(k, 0)
    return d

def _vsp_contractize_dict(obj):
    \"\"\"Mutate obj in place to provide stable keys used by UI.\"\"\"
    if not isinstance(obj, dict):
        return obj
    obj.setdefault("ok", True)

    # unify list payload
    if "items" not in obj:
        if isinstance(obj.get("findings"), list):
            obj["items"] = obj.get("findings")
        elif isinstance(obj.get("rows"), list):
            obj["items"] = obj.get("rows")
        elif isinstance(obj.get("data"), list):
            obj["items"] = obj.get("data")

    # total
    if obj.get("total") is None:
        items = obj.get("items")
        if isinstance(items, list):
            obj["total"] = len(items)

    # sev dict
    if "sev" in obj:
        obj["sev"] = _vsp_norm_sev(obj.get("sev"))
    elif "severity" in obj and isinstance(obj.get("severity"), dict):
        obj["sev"] = _vsp_norm_sev(obj.get("severity"))
    elif "severity_counts" in obj and isinstance(obj.get("severity_counts"), dict):
        obj["sev"] = _vsp_norm_sev(obj.get("severity_counts"))

    return obj

def _vsp_contractize_locals(_locals):
    \"\"\"Try to contractize common local vars j/data/out/resp/payload/res in handlers.\"\"\"
    for nm in ("j","data","out","resp","payload","res","result","ret"):
        v = _locals.get(nm)
        if isinstance(v, dict):
            _vsp_contractize_dict(v)

# ===== /{helper_tag} =====
"""
    s = s[:insert_at] + helper + s[insert_at:]

def inject_before_last_return(route_path: str):
    global s
    # find decorator line containing the route path
    # supports @app.get('/api/vsp/...') and @app.route('/api/vsp/...')
    pat = rf"(?s)(@.*\(\s*['\"]{re.escape(route_path)}['\"].*?\)\s*(?:\n@.*\n)*)\s*(def\s+[A-Za-z_]\w*\s*\([^)]*\)\s*:\s*\n)"
    m = re.search(pat, s)
    if not m:
        return False, "route_not_found"

    start_def = m.start(2)
    lines = s.splitlines(True)
    def_line_no = s[:start_def].count("\n")
    i = def_line_no

    # compute body indent
    body_indent = "    "
    j = i+1
    while j < len(lines):
        ln = lines[j]
        if ln.strip() == "":
            j += 1
            continue
        mi = re.match(r"^(\s+)", ln)
        if mi:
            body_indent = mi.group(1)
        break

    # function end = next top-level decorator/def
    k = i+1
    while k < len(lines):
        ln = lines[k]
        if re.match(r"^(def\s+|@)", ln):
            break
        k += 1

    func = "".join(lines[i:k])
    if f"CONTRACTIZE_{route_path}" in func:
        return True, "already"

    # inject before last return
    rets = list(re.finditer(r"(?m)^\s*return\b", func))
    at = rets[-1].start() if rets else len(func)

    inject = f"""{body_indent}# CONTRACTIZE_{route_path}
{body_indent}try:
{body_indent}    _vsp_contractize_locals(locals())
{body_indent}except Exception:
{body_indent}    pass

"""
    func2 = func[:at] + inject + func[at:]
    s = "".join(lines[:i]) + func2 + "".join(lines[k:])
    return True, "patched"

routes = [
  "/api/vsp/dashboard_v3",
  "/api/vsp/dash_kpis",
  "/api/vsp/findings_page_v3",
  "/api/vsp/findings_v3",
  "/api/vsp/run_gate_v3",
  "/api/vsp/artifact_v3",
  "/api/vsp/run_file",
  "/api/vsp/runs_v3",
]

report=[]
for r in routes:
    ok, st = inject_before_last_return(r)
    report.append((r, ok, st))

p.write_text(s, encoding="utf-8")
print("[OK] inject report:")
for r, ok, st in report:
    print(" ", r, "=>", st)
PY

python3 -m py_compile vsp_demo_app.py

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"

# show keys for 3 main endpoints
for ep in dashboard_v3 dash_kpis findings_page_v3; do
  echo "== $ep keys =="
  curl -fsS "$BASE/api/vsp/$ep?rid=$RID&limit=20&offset=0" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"keys=",sorted(list(j.keys()))[:40],"total=",j.get("total"),"sev_type=",type(j.get("sev")).__name__)'
done

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"
