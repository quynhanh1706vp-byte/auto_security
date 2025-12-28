#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
MARK="VSP_P3_SETTINGS_KPI_MODE_LIVE_V1"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_kpimode_${TS}"
echo "[BACKUP] ${APP}.bak_kpimode_${TS}"

python3 - "$APP" "$MARK" <<'PY'
from pathlib import Path
import re, sys, py_compile

app = Path(sys.argv[1])
mark = sys.argv[2]
s = app.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

# Find a function block that handles settings_v2
# Heuristics: route contains "settings_v2" OR function name contains "settings_v2"
idx = s.find("settings_v2")
if idx < 0:
    raise SystemExit("[ERR] cannot find 'settings_v2' in vsp_demo_app.py")

# Find nearest preceding "def " before idx
def_pos = s.rfind("\ndef ", 0, idx)
if def_pos < 0:
    def_pos = s.rfind("def ", 0, idx)
if def_pos < 0:
    raise SystemExit("[ERR] cannot locate handler def for settings_v2")

# Determine end of function block: next "\ndef " after def_pos
next_def = s.find("\ndef ", def_pos + 1)
if next_def < 0:
    next_def = len(s)

block = s[def_pos:next_def]

if mark in block:
    print("[OK] already patched in block:", mark)
    sys.exit(0)

# Find return jsonify(var) inside block and capture var name
m = re.search(r"return\s+jsonify\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", block)
var = None
if m:
    var = m.group(1)
else:
    # try flask.jsonify(...)
    m2 = re.search(r"return\s+\w*\.jsonify\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", block)
    if m2:
        var = m2.group(1)

if not var:
    # fallback: look for "return " with dict var
    # last resort: patch won't be applied
    raise SystemExit("[ERR] cannot find 'return jsonify(<var>)' in settings_v2 handler")

# Insert patch right before the return line
insert = f"""
    # ===================== {mark} =====================
    try:
        _dk = {var}.get("dash_kpis") or {{}}
        _tf = _dk.get("total_findings")
        if _tf is None:
            _tf = _dk.get("total")
        _tf = int(_tf or 0)
        if _tf > 0:
            {var}["kpi_mode"] = "live"
    except Exception:
        pass
    # ===================== /{mark} =====================
"""

# Replace first occurrence of the return jsonify(var) in this block
patched_block = re.sub(
    r"(return\s+jsonify\(\s*"+re.escape(var)+r"\s*\))",
    insert + r"\1",
    block,
    count=1
)

if patched_block == block:
    raise SystemExit("[ERR] failed to apply patch (no substitution)")

# Write back
new_s = s[:def_pos] + patched_block + s[next_def:]
app.write_text(new_s, encoding="utf-8")

# Compile check
py_compile.compile(str(app), doraise=True)
print("[OK] patched:", mark, "=>", str(app), "var=", var)
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] settings_v2 shows kpi_mode live when total_findings>0 =="
# Try both common endpoints to be safe
if curl -fsS "$BASE/api/ui/settings_v2" >/tmp/_s2.json 2>/dev/null; then
  echo "[OK] GET /api/ui/settings_v2"
  cat /tmp/_s2.json | grep -oE '"kpi_mode"\s*:\s*"[^"]+"' | head -n 1 || true
else
  echo "[WARN] /api/ui/settings_v2 not reachable; trying /api/vsp/settings_v2"
  curl -fsS "$BASE/api/vsp/settings_v2" >/tmp/_s2.json
  cat /tmp/_s2.json | grep -oE '"kpi_mode"\s*:\s*"[^"]+"' | head -n 1 || true
fi

echo "[DONE] settings_v2 auto-detect kpi_mode live applied."
