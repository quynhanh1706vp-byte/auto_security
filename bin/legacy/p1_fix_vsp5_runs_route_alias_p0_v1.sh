#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# file app chính (theo layout bạn đang dùng)
CAND=(
  "vsp_demo_app.py"
  "ui/vsp_demo_app.py"
  "wsgi_vsp_ui_gateway.py"
)

python3 - <<'PY'
from pathlib import Path
import time, re

TS=time.strftime("%Y%m%d_%H%M%S")
MARK="VSP_P0_ROUTE_ALIAS_VSP5_RUNS_V1"

cand=[Path(p) for p in ["vsp_demo_app.py","ui/vsp_demo_app.py","wsgi_vsp_ui_gateway.py"]]
target=None
for p in cand:
    if p.exists():
        s=p.read_text(encoding="utf-8", errors="replace")
        # ưu tiên file có Flask app routes
        if "@app" in s or "Flask(" in s:
            target=p
            break
if not target:
    print("[ERR] cannot find app file in candidates:", [str(p) for p in cand])
    raise SystemExit(2)

s=target.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[SKIP] already patched:", target)
    raise SystemExit(0)

bak=target.with_name(target.name+f".bak_route_alias_{TS}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP]", bak)

# đảm bảo có import redirect/url_for
if "from flask import" in s and "redirect" not in s:
    s=re.sub(r"from flask import ([^\n]+)",
             lambda m: "from flask import "+(m.group(1).strip()+", redirect").replace(", ,", ", "),
             s, count=1)
elif "import flask" in s and "redirect" not in s:
    # không chắc cấu trúc -> add safe import line
    s="from flask import redirect\n"+s

INJECT=f"""
# ===== {MARK} =====
try:
    @app.route("/vsp5/runs")
    def vsp5_runs_alias_v1():
        # keep commercial UX: no 404; unify to /runs
        return redirect("/runs", code=302)
except Exception:
    pass
# ===== end {MARK} =====
"""

# inject near other routes if possible, else append end
anchor = None
for pat in [r"@app\.route\(\"/runs\"\)", r"@app\.route\('/runs'\)", r"def\s+runs", r"@app\.route\(\"/vsp5\"\)"]:
    m=re.search(pat, s)
    if m:
        anchor=m.start()
        break

if anchor is not None:
    s = s[:anchor] + INJECT + "\n" + s[anchor:]
else:
    s = s.rstrip() + "\n\n" + INJECT + "\n"

target.write_text(s, encoding="utf-8")
print("[OK] injected route alias into:", target)
PY

python3 -m py_compile vsp_demo_app.py 2>/dev/null || true
python3 -m py_compile ui/vsp_demo_app.py 2>/dev/null || true
python3 -m py_compile wsgi_vsp_ui_gateway.py 2>/dev/null || true

echo "[OK] Patch done. Restart UI service then open /vsp5/runs (should redirect to /runs)."
