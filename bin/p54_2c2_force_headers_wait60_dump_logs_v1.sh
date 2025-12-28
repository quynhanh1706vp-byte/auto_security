#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p54_2c2_${TS}"
mkdir -p "$EVID"

APP="vsp_demo_app.py"
LOGDIR="/var/log/vsp-ui-8910"
ERRLOG="$LOGDIR/ui_8910.error.log"
ACCLOG="$LOGDIR/ui_8910.access.log"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need ls; need head; need curl; need awk; need sudo; need cp; need mkdir; need tail
command -v systemctl >/dev/null 2>&1 || true
command -v journalctl >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p54_2c2_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

cp -f "$APP" "$APP.bak_p54_2c2_${TS}"
echo "[OK] backup: $APP.bak_p54_2c2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P54_2C2_CANONICAL_HEADERS_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

lines=s.splitlines(True)

# Find after_request region
start_idx=None
for i,l in enumerate(lines):
    if "VSP_P52_2F_AFTER_REQUEST_HEADERS_V1" in l:
        start_idx=i; break
if start_idx is None:
    for i,l in enumerate(lines):
        if re.search(r'^\s*@app\.after_request\b', l):
            start_idx=i; break
if start_idx is None:
    raise SystemExit("[ERR] cannot find @app.after_request")

def_idx=None; def_indent=""
for j in range(start_idx, min(start_idx+80, len(lines))):
    m=re.match(r'^(\s*)def\s+\w+\s*\(\s*resp\b.*\)\s*:\s*$', lines[j])
    if m:
        def_idx=j; def_indent=m.group(1); break
if def_idx is None:
    raise SystemExit("[ERR] cannot find def after_request(resp...)")

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

lines.insert(def_idx+1, ins)
p.write_text("".join(lines), encoding="utf-8")
print("[OK] inserted canonical header override with indent_len=", len(body_indent))
PY

python3 -m py_compile "$APP" > "$EVID/py_compile.txt" 2>&1 || {
  echo "[ERR] py_compile failed; tail:"; tail -n 120 "$EVID/py_compile.txt" || true
  echo "[ROLLBACK] restoring backup"
  cp -f "$APP.bak_p54_2c2_${TS}" "$APP"
  exit 2
}

# restart
sudo systemctl restart "$SVC" || true

# wait up to 60s for /vsp5 200
ok=0
: > "$EVID/wait_vsp5_60s.txt"
for i in $(seq 1 60); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 5 "$BASE/vsp5" || true)"
  echo "t+${i}s code=$code" >> "$EVID/wait_vsp5_60s.txt"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 1
done

if [ "$ok" -ne 1 ]; then
  echo "[FAIL] /vsp5 not up within 60s -> dump logs then rollback"

  (systemctl status "$SVC" --no-pager || true) > "$EVID/systemctl_status.txt" 2>&1 || true
  (systemctl show "$SVC" -p ExecStart -p DropInPaths -p FragmentPath -p MainPID -p ActiveState --no-pager || true) > "$EVID/systemctl_show.txt" 2>&1 || true
  (journalctl -u "$SVC" -n 220 --no-pager || true) > "$EVID/journal_tail.txt" 2>&1 || true
  (ss -ltnp 2>/dev/null | grep -E ':(8910)\b' || true) > "$EVID/ss_8910.txt" 2>&1 || true

  if [ -f "$ERRLOG" ]; then tail -n 220 "$ERRLOG" > "$EVID/varlog_error_tail.txt" 2>&1 || true; fi
  if [ -f "$ACCLOG" ]; then tail -n 120 "$ACCLOG" > "$EVID/varlog_access_tail.txt" 2>&1 || true; fi

  cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

  echo "[ROLLBACK] restoring backup + restart"
  cp -f "$APP.bak_p54_2c2_${TS}" "$APP"
  sudo systemctl restart "$SVC" || true
  exit 2
fi

echo "[OK] /vsp5 is up (200) -> health 10/10"
ok10=1
: > "$EVID/health_10x.txt"
for i in $(seq 1 10); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 6 "$BASE/vsp5" || true)"
  echo "try#$i code=$code" >> "$EVID/health_10x.txt"
  [ "$code" = "200" ] || ok10=0
  sleep 0.35
done
[ "$ok10" -eq 1 ] || echo "[WARN] /vsp5 not 10/10 (non-fatal; still rerun P54)"

bash bin/p54_commercial_gate_v2_headers_sorted_source_markers_v1.sh > "$EVID/p54_rerun.log" 2>&1 || true

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
echo "[DONE] P54.2c2 APPLIED + reran P54 (see $EVID/p54_rerun.log)"
