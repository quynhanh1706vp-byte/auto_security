#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_2f2_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need ls; need head; need sudo; need cp; need mkdir
command -v systemctl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p52_2f2_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

cp -f "$APP" "$APP.bak_p52_2f2_${TS}"
echo "[OK] backup: $APP.bak_p52_2f2_${TS}" | tee "$EVID/backup.txt" >/dev/null

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# We expect the P52.2f block exists; harden it by replacing setdefault(...) with explicit assignment.
# Only touch inside the block marker to be safe.
start = s.find("VSP_P52_2F_AFTER_REQUEST_HEADERS_V1")
if start < 0:
    raise SystemExit("[ERR] P52.2f marker not found in vsp_demo_app.py")

# take a window around the block
win_start = max(0, start - 200)
win_end = min(len(s), start + 1500)
win = s[win_start:win_end]

before = win

win = win.replace('resp.headers.setdefault("X-Content-Type-Options", "nosniff")',
                  'resp.headers["X-Content-Type-Options"] = "nosniff"')
win = win.replace('resp.headers.setdefault("Referrer-Policy", "same-origin")',
                  'resp.headers["Referrer-Policy"] = "same-origin"')
win = win.replace('resp.headers.setdefault("X-Frame-Options", "SAMEORIGIN")',
                  'resp.headers["X-Frame-Options"] = "SAMEORIGIN"')

if win == before:
    print("[WARN] no changes (maybe already forced)")
else:
    s = s[:win_start] + win + s[win_end:]
    p.write_text(s, encoding="utf-8")
    print("[OK] forced override of hardening headers in P52.2f block")
PY

python3 -m py_compile "$APP" > "$EVID/py_compile.txt" 2>&1 || {
  echo "[ERR] py_compile failed; rollback"; cp -f "$APP.bak_p52_2f2_${TS}" "$APP"; exit 2;
}

sudo systemctl restart "$SVC" || true
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
echo "[DONE] P52.2f2 PASS (rerun P51.2 to see fp_count)"
