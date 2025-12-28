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
cp -f "$APP" "${APP}.bak_healthz_rid_${TS}"
echo "[BACKUP] ${APP}.bak_healthz_rid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P0_HEALTHZ_V1" not in s:
    raise SystemExit("[ERR] healthz marker not found; apply healthz first")

# Replace _health_rid_latest_gate_root() body with folder-based resolver
pat = r"def _health_rid_latest_gate_root\(\):\n\s*# Best effort:.*?\n\s*return os\.environ\.get\(\"VSP_RID_LATEST\".*?\)\n"
m = re.search(pat, s, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot locate _health_rid_latest_gate_root() to patch")

new_func = r'''def _health_rid_latest_gate_root():
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
    return best or ""\n'''

s2 = s[:m.start()] + new_func + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] healthz now auto-picks rid_latest_gate_root from out_ci")
PY

echo "== compile check =="
python3 -m py_compile "$APP"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] healthz rid_latest auto-pick installed."
