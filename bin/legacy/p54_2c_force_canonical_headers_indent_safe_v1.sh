#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p54_2c_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need ls; need head; need curl; need awk; need sudo; need cp; need mkdir
command -v systemctl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p54_2c_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

cp -f "$APP" "$APP.bak_p54_2c_${TS}"
echo "[OK] backup: $APP.bak_p54_2c_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P54_2C_CANONICAL_HEADERS_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

lines=s.splitlines(True)

# Prefer patch near existing after_request marker if present
start_idx = None
for i,l in enumerate(lines):
    if "VSP_P52_2F_AFTER_REQUEST_HEADERS_V1" in l:
        start_idx = i
        break

# Fallback: find @app.after_request
if start_idx is None:
    for i,l in enumerate(lines):
        if re.search(r'^\s*@app\.after_request\b', l):
            start_idx = i
            break
if start_idx is None:
    raise SystemExit("[ERR] cannot find @app.after_request")

# Find def line within next ~25 lines
def_idx=None
def_indent=""
for j in range(start_idx, min(start_idx+40, len(lines))):
    m=re.match(r'^(\s*)def\s+\w+\s*\(\s*resp\s*\)\s*:\s*$', lines[j])
    if m:
        def_idx=j
        def_indent=m.group(1)
        break
if def_idx is None:
    # more generic signature (resp) maybe named differently, still capture indent
    for j in range(start_idx, min(start_idx+60, len(lines))):
        m=re.match(r'^(\s*)def\s+\w+\s*\(\s*resp\b.*\)\s*:\s*$', lines[j])
        if m:
            def_idx=j
            def_indent=m.group(1)
            break
if def_idx is None:
    raise SystemExit("[ERR] cannot find def after_request(resp) near decorator")

body_indent = def_indent + " " * 4

ins = (
f"{body_indent}# {MARK}\n"
f"{body_indent}# Canonical cache + hardening headers (override) to eliminate per-route drift.\n"
f"{body_indent}resp.headers['Cache-Control'] = 'no-store'\n"
f"{body_indent}resp.headers['Pragma'] = 'no-cache'\n"
f"{body_indent}resp.headers['Expires'] = '0'\n"
f"{body_indent}resp.headers['X-Content-Type-Options'] = 'nosniff'\n"
f"{body_indent}resp.headers['Referrer-Policy'] = 'same-origin'\n"
f"{body_indent}resp.headers['X-Frame-Options'] = 'SAMEORIGIN'\n"
)

# Insert right after def line (next line)
insert_at = def_idx + 1
lines.insert(insert_at, ins)

p.write_text("".join(lines), encoding="utf-8")
print("[OK] inserted canonical header override with indent_len=", len(body_indent))
PY

# compile with evidence
python3 -m py_compile "$APP" > "$EVID/py_compile.txt" 2>&1 || {
  echo "[ERR] py_compile failed; see $EVID/py_compile.txt"
  echo "---- py_compile tail ----"
  tail -n 80 "$EVID/py_compile.txt" || true
  echo "[ROLLBACK] restoring backup"
  cp -f "$APP.bak_p54_2c_${TS}" "$APP"
  exit 2
}

sudo systemctl restart "$SVC" || true

# health 10/10
ok=1
: > "$EVID/health_10x.txt"
for i in $(seq 1 10); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 6 "$BASE/vsp5" || true)"
  echo "try#$i code=$code" >> "$EVID/health_10x.txt"
  [ "$code" = "200" ] || ok=0
  sleep 0.35
done
if [ "$ok" -ne 1 ]; then
  echo "[ERR] /vsp5 not stable 10/10; rollback"
  cp -f "$APP.bak_p54_2c_${TS}" "$APP"
  sudo systemctl restart "$SVC" || true
  exit 2
fi
echo "[OK] /vsp5 stable 10/10"

# rerun P54 gate v2
bash bin/p54_commercial_gate_v2_headers_sorted_source_markers_v1.sh > "$EVID/p54_rerun.log" 2>&1 || true

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
echo "[DONE] P54.2c APPLIED + reran P54 (see $EVID/p54_rerun.log)"
