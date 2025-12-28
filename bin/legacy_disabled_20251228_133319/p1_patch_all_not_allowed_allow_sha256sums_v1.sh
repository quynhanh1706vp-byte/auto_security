#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
MARK="VSP_P1_ALLOW_SHA256SUMS_NOT_ALLOWED_V1"

# (optional) dọn file old dễ gây py_compile fail (không ảnh hưởng runtime)
mkdir -p "$ROOT/_trash_py_${TS}"
for f in "$ROOT"/vsp_demo_app_old_*.py; do
  [ -f "$f" ] || continue
  mv -f "$f" "$ROOT/_trash_py_${TS}/"
done

python3 - <<'PY'
import os, re, shutil
from pathlib import Path

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
TS = os.environ["TS"]
MARK = "VSP_P1_ALLOW_SHA256SUMS_NOT_ALLOWED_V1"

def is_skip(p: Path):
    n = p.name
    if n.endswith(".py") is False: return True
    if ".bak_" in n: return True
    if "_trash_py_" in str(p): return True
    if "_old_" in n: return True
    return False

targets=[]
for p in ROOT.rglob("*.py"):
    if is_skip(p): 
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if ('"err":"not allowed"' in s) or ("err\": \"not allowed\"" in s) or ("err': 'not allowed'" in s) or ("err\":'not allowed'" in s):
        targets.append(p)

print("[INFO] files with err:not allowed =", len(targets))
patched=[]

for p in targets:
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[SKIP] already:", p.name)
        continue

    # patch every return line containing not allowed
    lines = s.splitlines(True)
    out=[]
    changed=False

    for ln in lines:
        m = re.match(r'^([ \t]*)return\b.*not allowed.*$', ln)
        if m:
            ind = m.group(1)
            inject = (
f"{ind}# {MARK}: allow reports/SHA256SUMS.txt (commercial audit)\n"
f"{ind}try:\n"
f"{ind}    _rid = (request.args.get('rid','') or request.args.get('run_id','') or request.args.get('run','') or '').strip()\n"
f"{ind}    _rel = (request.args.get('name','') or request.args.get('path','') or request.args.get('rel','') or '').strip().lstrip('/')\n"
f"{ind}    if _rid and _rel == 'reports/SHA256SUMS.txt':\n"
f"{ind}        from pathlib import Path as _P\n"
f"{ind}        _fp = _P('/home/test/Data/SECURITY_BUNDLE/out') / _rid / 'reports' / 'SHA256SUMS.txt'\n"
f"{ind}        if _fp.exists():\n"
f"{ind}            return send_file(str(_fp), as_attachment=True)\n"
f"{ind}except Exception:\n"
f"{ind}    pass\n"
            )
            out.append(inject)
            out.append(ln)
            changed=True
        else:
            out.append(ln)

    if not changed:
        print("[WARN] matched file but no patch point:", p.name)
        continue

    bak = p.with_suffix(p.suffix + f".bak_allowsha_notallowed_{TS}")
    shutil.copy2(p, bak)
    p.write_text("".join(out) + f"\n# {MARK}\n", encoding="utf-8")
    patched.append(p)

print("[OK] patched files:", [x.name for x in patched])
PY

# compile ONLY key runtime files (không compile toàn thư mục để tránh file test/old)
python3 -m py_compile vsp_runs_reports_bp.py vsp_demo_app.py wsgi_vsp_ui_gateway.py 2>/dev/null || true
python3 -m py_compile vsp_runs_reports_bp.py

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="btl86-connector_RUN_20251127_095755_000599"
echo "RID=$RID"
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 25
