#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p54_2b_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need ls; need head; need curl; need awk; need sudo; need cp; need mkdir
command -v systemctl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p54_2b_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

cp -f "$APP" "$APP.bak_p54_2b_${TS}"
echo "[OK] backup: $APP.bak_p54_2b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# We patch inside existing after_request block marker if present, otherwise we insert a new safe block.
MARK="VSP_P54_2B_CANONICAL_HEADERS_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Prefer to locate the existing P52.2f marker block and extend it.
anchor = s.find("VSP_P52_2F_AFTER_REQUEST_HEADERS_V1")
if anchor < 0:
    # fallback: find first @app.after_request
    m=re.search(r'(?m)^\s*@app\.after_request\s*\n\s*def\s+\w+\s*\(\s*resp\s*\)\s*:', s)
    if not m:
        raise SystemExit("[ERR] cannot find after_request to patch")
    anchor = m.start()

# Insert an override block near the start of after_request function body.
# Strategy: find "def ...(resp):" line after anchor, then insert right after it.
m=re.search(r'(?m)^\s*def\s+\w+\s*\(\s*resp\s*\)\s*:\s*$', s[anchor:])
if not m:
    raise SystemExit("[ERR] cannot locate def after_request(...)")
def_line_start = anchor + m.start()
def_line_end = anchor + m.end()

ins = f"""
    # {MARK}
    # Canonical cache + hardening headers for commercial consistency across 5 tabs.
    # Override (not setdefault) to eliminate per-route drift.
    resp.headers["Cache-Control"] = "no-store"
    resp.headers["Pragma"] = "no-cache"
    resp.headers["Expires"] = "0"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Referrer-Policy"] = "same-origin"
    resp.headers["X-Frame-Options"] = "SAMEORIGIN"
"""

# Insert after the def line (next newline)
insert_pos = s.find("\n", def_line_end) + 1
if insert_pos <= 0:
    raise SystemExit("[ERR] failed to compute insert_pos")

s = s[:insert_pos] + ins + s[insert_pos:]
p.write_text(s, encoding="utf-8")
print("[OK] inserted canonical header override into after_request")
PY

python3 -m py_compile "$APP" > "$EVID/py_compile.txt" 2>&1 || {
  echo "[ERR] py_compile failed -> rollback"; cp -f "$APP.bak_p54_2b_${TS}" "$APP"; exit 2;
}

sudo systemctl restart "$SVC" || true

# Health 10/10 for /vsp5
ok=1
: > "$EVID/health_10x.txt"
for i in $(seq 1 10); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 6 "$BASE/vsp5" || true)"
  echo "try#$i code=$code" >> "$EVID/health_10x.txt"
  [ "$code" = "200" ] || ok=0
  sleep 0.35
done
if [ "$ok" -ne 1 ]; then
  echo "[ERR] /vsp5 not stable 10/10; rollback"; cp -f "$APP.bak_p54_2b_${TS}" "$APP"; sudo systemctl restart "$SVC" || true; exit 2;
fi
echo "[OK] /vsp5 stable 10/10"

# Rerun P54 gate v2
bash bin/p54_commercial_gate_v2_headers_sorted_source_markers_v1.sh > "$EVID/p54_rerun.log" 2>&1 || true

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
echo "[DONE] P54.2b APPLIED + reran P54 (see $EVID/p54_rerun.log and attached evidence)"
