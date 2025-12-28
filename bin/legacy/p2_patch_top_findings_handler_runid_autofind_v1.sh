#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need find; need curl

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_TOPFIND_RUNID_CONTRACT_AUTOFIND_V1"

python3 - <<'PY'
from pathlib import Path
import re, sys, py_compile, time

root = Path(".")
skip_dirs = {".venv","venv","node_modules","out_ci",".git","static","templates"}
candidates = []

for p in root.rglob("*.py"):
    if any(part in skip_dirs for part in p.parts):
        continue
    try:
        txt = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "/api/vsp/top_findings_v1" in txt:
        candidates.append(p)

if not candidates:
    print("[ERR] no python file contains '/api/vsp/top_findings_v1'")
    sys.exit(2)

# pick first candidate with decorator route
target = None
for p in candidates:
    txt = p.read_text(encoding="utf-8", errors="replace")
    if re.search(r"@.*route\([^)]*/api/vsp/top_findings_v1", txt):
        target = p
        break
if target is None:
    target = candidates[0]

txt = target.read_text(encoding="utf-8", errors="replace")
if "VSP_P2_TOPFIND_RUNID_CONTRACT_AUTOFIND_V1" in txt:
    print("[OK] already patched:", target)
    py_compile.compile(str(target), doraise=True)
    sys.exit(0)

bak = target.with_suffix(target.suffix + f".bak_topfind_runid_{int(time.time())}")
bak.write_text(txt, encoding="utf-8")
print("[BACKUP]", bak)

# patch strategy:
# inside handler for this route, right before returning jsonify(...),
# inject code that sets run_id using current_app.view_functions rid_latest.
pat = re.compile(
    r"(@[^\n]*route\([^\n]*?/api/vsp/top_findings_v1[^\n]*\)\s*\n"
    r"(?:@[^\n]*\n)*"
    r"def\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*:\s*\n"
    r"(?P<body>(?:[ \t]+.*\n)+))",
    re.M
)
m = pat.search(txt)
if not m:
    print("[ERR] found file but cannot parse function block:", target)
    sys.exit(2)

body = m.group("body")

# find a "return jsonify(X)" line in body
mret = re.search(r"(?m)^(?P<ind>[ \t]+)return\s+jsonify\((?P<var>[A-Za-z_]\w*)\)\s*$", body)
if not mret:
    # fallback: return jsonify({...})
    mret2 = re.search(r"(?m)^(?P<ind>[ \t]+)return\s+jsonify\(\{", body)
    if not mret2:
        print("[ERR] cannot find 'return jsonify(...)' in handler body:", target)
        sys.exit(2)
    ind = mret2.group("ind")
    inject = (
        f"{ind}# {MARK}\n"
        f"{ind}try:\n"
        f"{ind}    from flask import current_app\n"
        f"{ind}    _rid=None\n"
        f"{ind}    for _ep,_fn in (getattr(current_app,'view_functions',{{}}) or {{}}).items():\n"
        f"{ind}        if 'rid_latest' not in (_ep or ''):\n"
        f"{ind}            continue\n"
        f"{ind}        try:\n"
        f"{ind}            _r=_fn()\n"
        f"{ind}            _j=None\n"
        f"{ind}            if hasattr(_r,'get_json'):\n"
        f"{ind}                _j=_r.get_json(silent=True)\n"
        f"{ind}            elif isinstance(_r,tuple) and _r and hasattr(_r[0],'get_json'):\n"
        f"{ind}                _j=_r[0].get_json(silent=True)\n"
        f"{ind}            if isinstance(_j,dict) and (_j.get('rid') or _j.get('run_id')):\n"
        f"{ind}                _rid=_j.get('rid') or _j.get('run_id')\n"
        f"{ind}                break\n"
        f"{ind}        except Exception:\n"
        f"{ind}            continue\n"
        f"{ind}    # NOTE: if you build dict j later, ensure to set j['run_id']=_rid\n"
        f"{ind}except Exception:\n"
        f"{ind}    pass\n"
    )
    body2 = body.replace(mret2.group(0), inject + mret2.group(0))
    txt2 = txt[:m.start("body")] + body2 + txt[m.end("body"):]
else:
    ind = mret.group("ind")
    var = mret.group("var")
    inject = (
        f"{ind}# {MARK}\n"
        f"{ind}try:\n"
        f"{ind}    from flask import current_app\n"
        f"{ind}    if isinstance({var}, dict) and not {var}.get('run_id'):\n"
        f"{ind}        _rid=None\n"
        f"{ind}        for _ep,_fn in (getattr(current_app,'view_functions',{{}}) or {{}}).items():\n"
        f"{ind}            if 'rid_latest' not in (_ep or ''):\n"
        f"{ind}                continue\n"
        f"{ind}            try:\n"
        f"{ind}                _r=_fn()\n"
        f"{ind}                _j=None\n"
        f"{ind}                if hasattr(_r,'get_json'):\n"
        f"{ind}                    _j=_r.get_json(silent=True)\n"
        f"{ind}                elif isinstance(_r,tuple) and _r and hasattr(_r[0],'get_json'):\n"
        f"{ind}                    _j=_r[0].get_json(silent=True)\n"
        f"{ind}                if isinstance(_j,dict) and (_j.get('rid') or _j.get('run_id')):\n"
        f"{ind}                    _rid=_j.get('rid') or _j.get('run_id')\n"
        f"{ind}                    break\n"
        f"{ind}            except Exception:\n"
        f"{ind}                continue\n"
        f"{ind}        if _rid:\n"
        f"{ind}            {var}['run_id']=_rid\n"
        f"{ind}            {var}.setdefault('marker','{MARK}')\n"
        f"{ind}except Exception:\n"
        f"{ind}    pass\n"
    )
    body2 = body.replace(mret.group(0), inject + mret.group(0))
    txt2 = txt[:m.start("body")] + body2 + txt[m.end("body"):]

target.write_text(txt2, encoding="utf-8")
py_compile.compile(str(target), doraise=True)
print("[OK] patched:", target)
PY

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== quick check =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid"))')"
echo "rid_latest=$RID"
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=1" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"run_id=",j.get("run_id"),"marker=",j.get("marker"),"total=",j.get("total"))'
