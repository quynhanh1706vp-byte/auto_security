#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need bash; need awk; need sed; need grep; need head; need tail; need wc; need curl; need python3
need systemctl; need sudo
command -v ss >/dev/null 2>&1 || true
command -v journalctl >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
B="$OUT/p47_debug_${TS}"
mkdir -p "$B"

echo "== [P47-DEBUG] $TS ==" | tee "$B/README.txt"
echo "SVC=$SVC" | tee -a "$B/README.txt"
echo "BASE=$BASE" | tee -a "$B/README.txt"

# unit + override
UNIT_PATH="$(systemctl show -p FragmentPath --value "$SVC" 2>/dev/null || true)"
echo "$UNIT_PATH" > "$B/unit_path.txt" || true

echo "== unit file ==" | tee "$B/unit.txt"
if [ -n "${UNIT_PATH:-}" ] && sudo test -f "$UNIT_PATH"; then
  sudo sed -n '1,220p' "$UNIT_PATH" | tee -a "$B/unit.txt" >/dev/null
else
  echo "(unit path not found)" | tee -a "$B/unit.txt" >/dev/null
fi

OVCONF="/etc/systemd/system/${SVC}.d/override.conf"
echo "== override.conf ==" | tee "$B/override.txt"
if sudo test -f "$OVCONF"; then
  sudo sed -n '1,200p' "$OVCONF" | tee -a "$B/override.txt" >/dev/null
else
  echo "(no override.conf)" | tee -a "$B/override.txt" >/dev/null
fi

# status + is-active
{
  echo "== systemctl is-active =="
  systemctl is-active "$SVC" || true
  echo
  echo "== systemctl status (no-pager) =="
  systemctl status "$SVC" --no-pager || true
  echo
  echo "== systemctl show (key fields) =="
  systemctl show "$SVC" -p ActiveState -p SubState -p ExecStart -p MainPID -p FragmentPath -p DropInPaths -p Environment --no-pager || true
} | tee "$B/systemctl.txt" >/dev/null

# journal
if command -v journalctl >/dev/null 2>&1; then
  sudo journalctl -u "$SVC" --no-pager -n 250 > "$B/journal_tail.txt" || true
fi

# ports/process
if command -v ss >/dev/null 2>&1; then
  ss -lntp 2>/dev/null | egrep '(:8910|:8911|:8912|gunicorn|python)' > "$B/ports_ss.txt" || true
fi
ps auxww | egrep 'vsp_demo_app|gunicorn|wsgi_vsp_ui_gateway|vsp-ui-8910|8910' | head -n 200 > "$B/ps.txt" || true

# curl quick probes
{
  echo "== curl probes =="
  for p in /vsp5 /api/vsp/selfcheck_p0 /runs; do
    echo "-- $BASE$p --"
    curl -sS -o /dev/null -w "http_code=%{http_code} time_total=%{time_total}\n" --connect-timeout 2 --max-time 4 "$BASE$p" || echo "curl_failed"
  done
  echo
  echo "== try localhost:8911 (common mistake) =="
  curl -sS -o /dev/null -w "http_code=%{http_code} time_total=%{time_total}\n" --connect-timeout 2 --max-time 4 "http://127.0.0.1:8911/vsp5" || echo "curl_failed"
} | tee "$B/curl.txt" >/dev/null

# pack debug bundle
TAR="$OUT/p47_debug_${TS}.tar.gz"
tar -czf "$TAR" -C "$OUT" "p47_debug_${TS}"
echo "[OK] debug bundle: $TAR"
echo "[OK] folder: $B"
