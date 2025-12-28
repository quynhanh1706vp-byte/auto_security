#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_DASHV2_HARDEN_ALT_P0_V1"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_reorder_${TS}"
echo "[BACKUP] $F.bak_reorder_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_DASHV2_HARDEN_ALT_P0_V1"

# extract the marked block (if present)
pat = r"#\s*===\s*"+re.escape(MARK)+r"\s*===\s*\n.*?\n#\s*===\s*/"+re.escape(MARK)+r"\s*===\s*\n?"
m = re.search(pat, s, flags=re.S)
block = None
if m:
    block = m.group(0).rstrip() + "\n\n"
    s_wo = s[:m.start()] + s[m.end():]
else:
    s_wo = s

# find app = Flask(...) line
mapp = re.search(r"^app\s*=\s*Flask\([^\n]*\)\s*$", s_wo, flags=re.M)
if not mapp:
    raise SystemExit("[ERR] cannot find 'app = Flask(...)' in vsp_demo_app.py")

# if block missing, do nothing except ensure no decorator at file top
if block is None:
    # still guard: if file starts with @app.* before app defined, error out
    head = s_wo.splitlines()[:40]
    for i,ln in enumerate(head,1):
        if ln.lstrip().startswith("@app.") and i < (s_wo[:mapp.start()].count("\n")+1):
            raise SystemExit("[ERR] found @app.* before app=Flask; manual intervention needed")
    print("[OK] no marked block to move; app=Flask present")
    p.write_text(s_wo, encoding="utf-8")
    raise SystemExit(0)

# insert block right after app line
insert_at = mapp.end()
s_fixed = s_wo[:insert_at] + "\n\n" + block + s_wo[insert_at:]

# sanity: ensure no @app.* appears before app definition now
pre = s_fixed[:insert_at].splitlines()
for ln in pre:
    if ln.lstrip().startswith("@app."):
        raise SystemExit("[ERR] still has @app.* before app=Flask after fix")

p.write_text(s_fixed, encoding="utf-8")
print("[OK] moved block after app=Flask:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] start 8910 again then verify:"
echo "  python3 -c 'import wsgi_vsp_ui_gateway; print(\"wsgi ok\")'"
echo "  curl -sS http://127.0.0.1:8910/api/vsp/dashboard_commercial_v2_harden | jq . -C"
