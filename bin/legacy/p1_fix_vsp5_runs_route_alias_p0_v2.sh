#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import time, re

TS=time.strftime("%Y%m%d_%H%M%S")
MARK="VSP_P0_ROUTE_ALIAS_VSP5_RUNS_V2"

FILES=[
  Path("vsp_demo_app.py"),
  Path("ui/vsp_demo_app.py"),
  Path("wsgi_vsp_ui_gateway.py"),
]

INJECT=f"""
# ===== {MARK} =====
try:
    # prefer app if exists
    _app = globals().get("app", None)
    if _app is not None:
        @_app.route("/vsp5/runs")
        def vsp5_runs_alias_v2():
            from flask import redirect
            return redirect("/runs", code=302)
    # or blueprint if app not present
    _bp = globals().get("bp", None) or globals().get("runs_bp", None)
    if _bp is not None:
        @_bp.route("/vsp5/runs")
        def vsp5_runs_alias_bp_v2():
            from flask import redirect
            return redirect("/runs", code=302)
except Exception:
    pass
# ===== end {MARK} =====
"""

def patch(p: Path):
    if not p.exists():
        print("[SKIP] missing:", p)
        return False
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[SKIP] already patched:", p)
        return False
    bak=p.with_name(p.name+f".bak_alias_v2_{TS}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(s.rstrip()+"\n\n"+INJECT+"\n", encoding="utf-8")
    print("[OK] patched:", p, " backup:", bak)
    return True

changed=False
for f in FILES:
    changed = patch(f) or changed

print("[DONE] changed=", changed)
PY

# restart sạch UI :8910 (giống style bạn hay dùng)
echo "[INFO] restart clean :8910"
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true

# ưu tiên systemd nếu có, không có thì dùng script start của bạn
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q 'vsp-ui-8910'; then
  sudo systemctl restart vsp-ui-8910.service || true
else
  bin/p1_ui_8910_single_owner_start_v2.sh || true
fi

sleep 1

echo "== verify route =="
curl -sS -I http://127.0.0.1:8910/vsp5/runs | head -n 10
