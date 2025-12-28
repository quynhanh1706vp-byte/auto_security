#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_broken_rid_${TS}"
echo "[SNAPSHOT BROKEN] ${APP}.bak_broken_rid_${TS}"

echo "== find latest compiling backup =="
BEST="$(python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("vsp_demo_app.py")
baks = sorted(Path(".").glob("vsp_demo_app.py.bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)

for b in baks[:120]:
    try:
        tmp = Path("/tmp/_vsp_demo_try.py")
        tmp.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        py_compile.compile(str(tmp), doraise=True)
        print(b.as_posix())
        raise SystemExit(0)
    except Exception:
        continue

raise SystemExit(2)
PY
)" || { echo "[ERR] no compiling backup found"; exit 2; }

echo "[RESTORE] $BEST -> $APP"
cp -f "$BEST" "$APP"

echo "== apply patch (v2, safe) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P0_HEALTHZ_V1" not in s:
    raise SystemExit("[ERR] healthz marker not found; apply healthz first")

# Replace entire function _health_rid_latest_gate_root up to next def _health_degraded_tools_count
pat = r"def _health_rid_latest_gate_root\(\):\n(?P<body>.*?)(?=^def _health_degraded_tools_count\(\):\n)"
m = re.search(pat, s, flags=re.S | re.M)
if not m:
    raise SystemExit("[ERR] cannot locate _health_rid_latest_gate_root() block")

new_func = """def _health_rid_latest_gate_root():
    # Best effort:
    # 1) env VSP_RID_LATEST
    rid = os.environ.get("VSP_RID_LATEST", "").strip()
    if rid:
        return rid

    # 2) pick newest run dir that contains run_gate_summary.json (cheap filesystem scan)
    roots = [
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
    ]
    best = None
    best_m = 0.0
    for root in roots:
        try:
            if not root.is_dir():
                continue
            for d in root.iterdir():
                if not d.is_dir():
                    continue
                f = d / "run_gate_summary.json"
                if f.is_file() and f.stat().st_size > 0:
                    mt = f.stat().st_mtime
                    if mt > best_m:
                        best_m = mt
                        best = d.name
        except Exception:
            continue
    return best or ""
"""

s2 = s[:m.start()] + new_func + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched rid_latest_gate_root (no stray \\\\n)")
PY

echo "== compile check =="
python3 -m py_compile "$APP"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] healthz rid_latest auto-pick fixed."
