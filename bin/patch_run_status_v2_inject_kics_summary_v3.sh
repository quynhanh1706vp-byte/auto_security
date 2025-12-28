#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

ROUTE="/api/vsp/run_status_v2"
TARGET="vsp_demo_app.py"
[ -f "$TARGET" ] || { echo "[ERR] missing $TARGET"; exit 2; }
grep -q "$ROUTE" "$TARGET" || { echo "[ERR] route not found in $TARGET: $ROUTE"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TARGET" "$TARGET.bak_runstatusv2_kics_v3_${TS}"
echo "[BACKUP] $TARGET.bak_runstatusv2_kics_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

ROUTE = "/api/vsp/run_status_v2"
path = Path("vsp_demo_app.py")
t = path.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_STATUS_V2_INJECT_KICS_SUMMARY_V3 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# ---- ensure helpers exist (top-level) ----
if "# === VSP_KICS_HELPERS_V3 ===" not in t:
    helper = r"""
# === VSP_KICS_HELPERS_V3 ===
def _vsp_kics_summary_read_v3(ci_run_dir: str):
    try:
        from pathlib import Path as _P
        import json as _json
        fp = _P(ci_run_dir) / "kics" / "kics_summary.json"
        if not fp.exists():
            return None
        raw = fp.read_text(encoding="utf-8", errors="ignore") or ""
        obj = _json.loads(raw) if raw.lstrip().startswith("{") else None
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None

def _vsp_guess_ci_run_dir_from_rid_v3(rid: str):
    try:
        import glob, os
        if not rid:
            return None
        rid_norm = rid[4:] if rid.startswith("RUN_") else rid
        pats = [
            "/home/test/Data/*/out_ci/" + rid_norm,
            "/home/test/Data/*/*/out_ci/" + rid_norm,
            "/home/test/Data/*/out/" + rid_norm,
            "/home/test/Data/*/*/out/" + rid_norm,
        ]
        for pat in pats:
            for g in glob.glob(pat):
                if os.path.isdir(g):
                    return g
        return None
    except Exception:
        return None
# === END VSP_KICS_HELPERS_V3 ===

"""
    # insert after initial import block if possible
    m = re.search(r'(?ms)\A((?:\s*(?:from\s+\S+\s+import\s+.+|import\s+\S+).*\n)+)', t)
    if m:
        ins = m.end(1)
        t = t[:ins] + "\n" + helper + t[ins:]
    else:
        t = helper + "\n" + t

# ---- find handler: first def after ROUTE occurrence ----
idx = t.find(ROUTE)
if idx == -1:
    print("[ERR] cannot find route string")
    raise SystemExit(4)

mdef = re.search(r'(?m)^\s*def\s+(\w+)\s*\(([^)]*)\)\s*:', t[idx:])
if not mdef:
    # sometimes route is built dynamically; try search whole file for "run_status_v2" then def after it
    idx2 = t.find("run_status_v2")
    if idx2 != -1:
        mdef = re.search(r'(?m)^\s*def\s+(\w+)\s*\(([^)]*)\)\s*:', t[idx2:])
if not mdef:
    print("[ERR] cannot locate handler def after route marker")
    raise SystemExit(5)

fn_name = mdef.group(1)
print("[OK] handler =", fn_name)

# ---- isolate function block by indentation ----
defline = re.search(r'(?m)^(\s*)def\s+' + re.escape(fn_name) + r'\s*\([^)]*\)\s*:\s*$', t)
if not defline:
    defline = re.search(r'(?m)^(\s*)def\s+' + re.escape(fn_name) + r'\s*\([^)]*\)\s*:', t)
if not defline:
    print("[ERR] cannot re-find def line for handler:", fn_name)
    raise SystemExit(6)

base_indent = defline.group(1)
base_col = len(base_indent)

lines = t.splitlines(True)
# map defline.start -> line index
cum = 0
def_i = None
for i, line in enumerate(lines):
    if cum <= defline.start() < cum + len(line):
        def_i = i
        break
    cum += len(line)
if def_i is None:
    print("[ERR] internal mapping failed")
    raise SystemExit(7)

end_i = len(lines)
for j in range(def_i + 1, len(lines)):
    s = lines[j]
    if s.strip() == "":
        continue
    ind = len(s) - len(s.lstrip(" "))
    if ind <= base_col and (s.lstrip().startswith("def ") or s.lstrip().startswith("@")):
        end_i = j
        break

fn_text = "".join(lines[def_i:end_i])

# ---- find return jsonify(payload_var) ----
mret = re.search(r'(?m)^(\s*)return\s+.*\bjsonify\s*\(\s*([A-Za-z_]\w*)\s*\).*$', fn_text)
if not mret:
    # sometimes jsonify imported as flask.jsonify, still includes "jsonify("
    mret = re.search(r'(?m)^(\s*)return\s+.*\b\w*jsonify\w*\s*\(\s*([A-Za-z_]\w*)\s*\).*$', fn_text)

if not mret:
    print("[ERR] cannot find return ... jsonify(<var>) in handler. Please show tail of handler.")
    raise SystemExit(8)

ret_indent = mret.group(1)
payload_var = mret.group(2)
print("[OK] payload var =", payload_var)

inject = (
    ret_indent + TAG + "\n"
    + ret_indent + "try:\n"
    + ret_indent + f"    _rid = str({payload_var}.get('rid_norm') or {payload_var}.get('run_id') or {payload_var}.get('request_id') or '')\n"
    + ret_indent + "    if not _rid:\n"
    + ret_indent + "        try:\n"
    + ret_indent + "            from flask import request as _req\n"
    + ret_indent + "            _rid = (_req.path.rsplit('/',1)[-1] if getattr(_req,'path',None) else '')\n"
    + ret_indent + "        except Exception:\n"
    + ret_indent + "            _rid = ''\n"
    + ret_indent + f"    if not {payload_var}.get('ci_run_dir'):\n"
    + ret_indent + "        _g = _vsp_guess_ci_run_dir_from_rid_v3(_rid)\n"
    + ret_indent + "        if _g:\n"
    + ret_indent + f"            {payload_var}['ci_run_dir'] = _g\n"
    + ret_indent + f"    _ci = {payload_var}.get('ci_run_dir') or ''\n"
    + ret_indent + "    _ks = _vsp_kics_summary_read_v3(_ci) if _ci else None\n"
    + ret_indent + "    if isinstance(_ks, dict):\n"
    + ret_indent + f"        {payload_var}['kics_verdict'] = (_ks.get('verdict') or '')\n"
    + ret_indent + f"        {payload_var}['kics_counts']  = (_ks.get('counts') if isinstance(_ks.get('counts'), dict) else {{}})\n"
    + ret_indent + f"        {payload_var}['kics_total']   = int(_ks.get('total',0) or 0)\n"
    + ret_indent + "    else:\n"
    + ret_indent + f"        {payload_var}.setdefault('kics_verdict','')\n"
    + ret_indent + f"        {payload_var}.setdefault('kics_counts',{{}})\n"
    + ret_indent + f"        {payload_var}.setdefault('kics_total',0)\n"
    + ret_indent + "except Exception:\n"
    + ret_indent + f"    {payload_var}.setdefault('kics_verdict','')\n"
    + ret_indent + f"    {payload_var}.setdefault('kics_counts',{{}})\n"
    + ret_indent + f"    {payload_var}.setdefault('kics_total',0)\n"
    + ret_indent + "# === END VSP_RUN_STATUS_V2_INJECT_KICS_SUMMARY_V3 ===\n\n"
)

fn_text2 = fn_text[:mret.start()] + inject + fn_text[mret.start():]
full = "".join(lines)
full2 = full.replace(fn_text, fn_text2, 1)

path.write_text(full2, encoding="utf-8")
print("[OK] injected kics_summary into run_status_v2 response")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
