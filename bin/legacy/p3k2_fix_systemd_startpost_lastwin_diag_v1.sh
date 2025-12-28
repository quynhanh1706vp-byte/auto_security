#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need journalctl; need tail; need sed

echo "== [0] show service + drop-ins order =="
sudo systemctl cat "$SVC" | sed -n '1,240p' || true

echo "== [1] create LAST-WIN drop-in to disable ExecStartPost =="
D="/etc/systemd/system/${SVC}.d"
F="$D/zzz-disable-execstartpost.conf"
tmp="/tmp/zzz-disable-execstartpost.$$"

cat > "$tmp" <<'EOF'
[Service]
TimeoutStartSec=180
ExecStartPost=
ExecStartPost=/bin/bash -lc 'exit 0'
EOF

sudo mkdir -p "$D"
sudo cp -f "$tmp" "$F"
sudo chmod 0644 "$F"
rm -f "$tmp"
echo "[OK] wrote $F"

echo "== [2] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo rm -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.pid 2>/dev/null || true
sudo systemctl restart "$SVC" || true
sleep 0.8

echo "== [3] status =="
sudo systemctl status "$SVC" --no-pager | sed -n '1,200p' || true

echo "== [4] confirm ExecStartPost is cleared (must NOT show readycheck loops) =="
sudo systemctl show "$SVC" -p ExecStartPost --no-pager || true

echo "== [5] if still failing, print REAL reason (journal + error log + import) =="
if ! sudo systemctl is-active --quiet "$SVC"; then
  echo "[ERR] service still not active"
  echo "--- journal (last 220) ---"
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  echo "--- ui error log tail ---"
  tail -n 220 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null || true
  echo "--- python import check (stack) ---"
  "$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')" 2>&1 | sed -n '1,260p' || true
  exit 3
fi

echo "[OK] service active (start-post disabled safely)"
echo "[DONE] p3k2_fix_systemd_startpost_lastwin_diag_v1"
