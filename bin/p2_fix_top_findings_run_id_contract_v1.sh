#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_runid_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_runid_${TS}"

python3 - "$APP" <<'PY'
from pathlib import Path
import re, py_compile, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P2_TOPFIND_RUNID_CONTRACT_V1"
if marker in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

# Try to locate the top_findings_v1 route block by decorator or function name
# We patch by injecting a small post-processing right before returning jsonify(...)
# covering common patterns: return jsonify(j) / return jsonify({...})
patterns = [
    r"(@app\.route\(['\"]\/api\/vsp\/top_findings_v1['\"][\s\S]{0,8000}?def\s+top_findings_v1[\s\S]{0,12000}?return\s+jsonify\((?P<var>[A-Za-z_][A-Za-z0-9_]*)\))",
    r"(@app\.route\(['\"]\/api\/vsp\/top_findings_v1['\"][\s\S]{0,8000}?def\s+api_vsp_top_findings_v1[\s\S]{0,12000}?return\s+jsonify\((?P<var>[A-Za-z_][A-Za-z0-9_]*)\))",
]

patched = False
for pat in patterns:
    m = re.search(pat, s)
    if not m:
        continue
    var = m.group("var")
    insert = f"""
    # {marker}
    try:
        # force run_id contract: must not be None; prefer rid_latest
        _rid = None
        try:
            _rl = rid_latest()  # existing helper in app
            if isinstance(_rl, dict):
                _rid = _rl.get("rid")
        except Exception:
            _rid = None
        if not {var}.get("run_id"):
            {var}["run_id"] = _rid
        {var}.setdefault("marker", "{marker}")
    except Exception:
        pass
"""
    # Insert right before the matched return jsonify(var)
    start, end = m.span()
    # find the exact "return jsonify(var)" within the matched block to insert before it
    sub = s[start:end]
    sub2 = re.sub(rf"\n(\s*)return\s+jsonify\({re.escape(var)}\)\s*$",
                  insert + r"\n\1return jsonify(" + var + r")",
                  sub, flags=re.M)
    if sub2 != sub:
        s = s[:start] + sub2 + s[end:]
        patched = True
        break

if not patched:
    # fallback: patch any function that returns jsonify(j) and contains "top_findings_v1" string
    m = re.search(r"(def\s+[A-Za-z0-9_]*top_findings[A-Za-z0-9_]*\s*\([\s\S]{0,12000}?return\s+jsonify\((?P<var>[A-Za-z_][A-Za-z0-9_]*)\))", s)
    if not m:
        print("[ERR] could not locate top_findings_v1 handler to patch")
        sys.exit(2)
    var = m.group("var")
    start, end = m.span()
    sub = s[start:end]
    insert = f"""
    # {marker}
    try:
        _rid = None
        try:
            _rl = rid_latest()
            if isinstance(_rl, dict):
                _rid = _rl.get("rid")
        except Exception:
            _rid = None
        if not {var}.get("run_id"):
            {var}["run_id"] = _rid
        {var}.setdefault("marker", "{marker}")
    except Exception:
        pass
"""
    sub2 = re.sub(rf"\n(\s*)return\s+jsonify\({re.escape(var)}\)\s*$",
                  insert + r"\n\1return jsonify(" + var + r")",
                  sub, flags=re.M)
    s = s[:start] + sub2 + s[end:]
    patched = True

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched top_findings_v1 run_id contract")
PY

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== quick check =="
RID="$(curl -fsS http://127.0.0.1:8910/api/vsp/rid_latest | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid"))')"
echo "rid_latest=$RID"
curl -fsS "http://127.0.0.1:8910/api/vsp/top_findings_v1?limit=1" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"run_id=",j.get("run_id"),"marker=",j.get("marker")); print("expect=", "'"$RID"'" )'
