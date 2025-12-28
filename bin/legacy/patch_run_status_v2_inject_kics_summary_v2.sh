#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

ROUTE="/api/vsp/run_status_v2"
CANDIDATES=(
  "vsp_demo_app.py"
  "run_api/vsp_run_api_v1.py"
  "run_api/vsp_run_api_v2.py"
  "run_api/vsp_run_api_v1_fallback.py"
  "ui/vsp_demo_app.py"
)

TARGET=""
for f in "${CANDIDATES[@]}"; do
  if [ -f "$f" ] && grep -q "$ROUTE" "$f"; then
    TARGET="$f"
    break
  fi
done

if [ -z "$TARGET" ]; then
  echo "[ERR] cannot find route '$ROUTE' in known candidates."
  echo "Try: grep -R \"$ROUTE\" -n . | head"
  exit 2
fi

echo "[OK] target file: $TARGET"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TARGET" "$TARGET.bak_runstatusv2_kics_v2_${TS}"
echo "[BACKUP] $TARGET.bak_runstatusv2_kics_v2_${TS}"

python3 - <<PY
from pathlib import Path
import re

path = Path("$TARGET")
t = path.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_STATUS_V2_INJECT_KICS_SUMMARY_V2 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# 1) ensure helper funcs exist in this file
if "_vsp_kics_summary_read_v2" not in t:
    helper = """
# === VSP_KICS_HELPERS_V2 ===
def _vsp_kics_summary_read_v2(ci_run_dir: str):
    try:
        from pathlib import Path as _P
        import json as _json
        fp = _P(ci_run_dir) / "kics" / "kics_summary.json"
        if not fp.exists():
            return None
        obj = _json.loads(fp.read_text(encoding="utf-8", errors="ignore") or "{}")
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None

def _vsp_guess_ci_run_dir_from_rid_v2(rid: str):
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
# === END VSP_KICS_HELPERS_V2 ===

"""
    # insert after imports (best effort)
    m = re.search(r'(?m)^(?:from\\s+\\S+\\s+import\\s+\\S+|import\\s+\\S+).*$\\n', t)
    if m:
        # find end of initial import block
        m2 = re.search(r'(?ms)\\A((?:\\s*(?:from\\s+\\S+\\s+import\\s+\\S+|import\\s+\\S+).*$\\n)+)', t)
        if m2:
            ins = m2.end(1)
            t = t[:ins] + "\\n" + helper + t[ins:]
        else:
            t = helper + t
    else:
        t = helper + t

# 2) locate handler by route decorator OR url_rule with route string
# Try decorator: @app.route("/api/vsp/run_status_v2/<...>")
decor = re.search(r'(?ms)^\\s*@\\w+\\.route\\(\\s*[\\\'"]' + re.escape("/api/vsp/run_status_v2") + r'[^\\\'"]*[\\\'"][^\\)]*\\)\\s*\\n\\s*def\\s+(\\w+)\\s*\\(([^)]*)\\)\\s*:', t)
fn_name = None
fn_args = None
fn_def_start = None

if decor:
    fn_name = decor.group(1)
    fn_args = decor.group(2)
    fn_def_start = decor.end()
else:
    # fallback: any occurrence of route string, then next "def ..."
    idx = t.find("/api/vsp/run_status_v2")
    if idx != -1:
        # search forward for def
        m = re.search(r'(?m)^\\s*def\\s+(\\w+)\\s*\\(([^)]*)\\)\\s*:', t[idx:])
        if m:
            fn_name = m.group(1)
            fn_args = m.group(2)
            fn_def_start = idx + m.end()

if not fn_name:
    print("[ERR] cannot locate handler def after route string")
    raise SystemExit(3)

print("[OK] handler =", fn_name, "args =", fn_args)

# 3) find full function block by indentation
# find def line start
defline = re.search(r'(?m)^(\\s*)def\\s+' + re.escape(fn_name) + r'\\s*\\(([^)]*)\\)\\s*:\\s*$', t)
if not defline:
    # fallback: find first "def fn_name(" anywhere
    defline = re.search(r'(?m)^(\\s*)def\\s+' + re.escape(fn_name) + r'\\s*\\(([^)]*)\\)\\s*:', t)
if not defline:
    print("[ERR] cannot re-find def line for handler")
    raise SystemExit(4)

base_indent = defline.group(1)
base_col = len(base_indent)
start = defline.end()

lines = t.splitlines(True)
# compute absolute offsets for scanning
# find the def line index
cum = 0
def_i = None
for i, line in enumerate(lines):
    if cum <= defline.start() < cum + len(line):
        def_i = i
        break
    cum += len(line)
if def_i is None:
    print("[ERR] internal: cannot map def position to line index")
    raise SystemExit(5)

# find end line: first line with indent <= base_col and starts with "def " or "@"
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

# 4) find return line with *jsonify*(<var>)
mret = re.search(r'(?m)^(\\s*)return\\s+.*\\b\\w*jsonify\\w*\\s*\\(\\s*([A-Za-z_]\\w*)\\s*\\).*$', fn_text)
if not mret:
    print("[ERR] cannot find return ... jsonify(<var>) in handler. Need manual anchor.")
    raise SystemExit(6)

ret_indent = mret.group(1)
payload_var = mret.group(2)

inject = (
    ret_indent + TAG + "\\n"
    + ret_indent + "try:\\n"
    + ret_indent + f"    _rid = str({payload_var}.get('rid_norm') or {payload_var}.get('run_id') or {payload_var}.get('request_id') or '')\\n"
    + ret_indent + "    if not _rid:\\n"
    + ret_indent + "        # best-effort: use last path segment if request is available\\n"
    + ret_indent + "        try:\\n"
    + ret_indent + "            from flask import request as _req\\n"
    + ret_indent + "            _rid = (_req.path.rsplit('/',1)[-1] if getattr(_req,'path',None) else '')\\n"
    + ret_indent + "        except Exception:\\n"
    + ret_indent + "            _rid = ''\\n"
    + ret_indent + f"    if not {payload_var}.get('ci_run_dir'):\\n"
    + ret_indent + "        _g = _vsp_guess_ci_run_dir_from_rid_v2(_rid)\\n"
    + ret_indent + "        if _g:\\n"
    + ret_indent + f"            {payload_var}['ci_run_dir'] = _g\\n"
    + ret_indent + f"    _ci = {payload_var}.get('ci_run_dir') or ''\\n"
    + ret_indent + "    _ks = _vsp_kics_summary_read_v2(_ci) if _ci else None\\n"
    + ret_indent + "    if isinstance(_ks, dict):\\n"
    + ret_indent + f"        {payload_var}['kics_verdict'] = _ks.get('verdict','') or ''\\n"
    + ret_indent + f"        {payload_var}['kics_counts']  = _ks.get('counts',{{}}) if isinstance(_ks.get('counts'), dict) else {{}}\\n"
    + ret_indent + f"        {payload_var}['kics_total']   = int(_ks.get('total',0) or 0)\\n"
    + ret_indent + "    else:\\n"
    + ret_indent + f"        {payload_var}.setdefault('kics_verdict','')\\n"
    + ret_indent + f"        {payload_var}.setdefault('kics_counts',{{}})\\n"
    + ret_indent + f"        {payload_var}.setdefault('kics_total',0)\\n"
    + ret_indent + "except Exception:\\n"
    + ret_indent + f"    {payload_var}.setdefault('kics_verdict','')\\n"
    + ret_indent + f"    {payload_var}.setdefault('kics_counts',{{}})\\n"
    + ret_indent + f"    {payload_var}.setdefault('kics_total',0)\\n"
    + ret_indent + "# === END VSP_RUN_STATUS_V2_INJECT_KICS_SUMMARY_V2 ===\\n\\n"
)

# insert inject right before that return line
fn_text2 = fn_text[:mret.start()] + inject + fn_text[mret.start():]

# replace function text in full file
full = "".join(lines)
full2 = full.replace(fn_text, fn_text2, 1)

path.write_text(full2, encoding="utf-8")
print("[OK] injected before return jsonify(", payload_var, ") in handler", fn_name)
PY

python3 -m py_compile "$TARGET"
echo "[OK] py_compile OK"

echo "== restart service =="
sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== verify =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
