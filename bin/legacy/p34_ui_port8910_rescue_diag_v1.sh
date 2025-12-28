#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need awk; need grep
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl not found"; exit 2; }

echo "== [0] systemd state =="
sudo systemctl is-active "$SVC" || true
sudo systemctl show "$SVC" -p ActiveState -p SubState -p MainPID -p ExecMainStatus -p ExecMainCode --no-pager || true

echo "== [1] restart =="
sudo systemctl restart "$SVC" || true

echo "== [2] quick port check (ss) =="
if command -v ss >/dev/null 2>&1; then
  ss -lntp | awk '/:8910 / || NR==1 {print}'
else
  echo "[WARN] ss not found"
fi

echo "== [3] try curl selfcheck (retry fast) =="
ok=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/tmp/_vsp_selfcheck.json 2>/tmp/_vsp_curl.err; then
    echo "[OK] curl selfcheck_p0 succeeded (try#$i)"
    head -c 400 /tmp/_vsp_selfcheck.json; echo
    ok=1
    break
  else
    echo "[WARN] curl failed (try#$i): $(tr -d '\n' </tmp/_vsp_curl.err | head -c 200)"
    # micro backoff (không “đợi”, chỉ retry kỹ thuật)
    python3 - <<'PY'
import time; time.sleep(0.2)
PY
  fi
done

if [ "$ok" -eq 1 ]; then
  echo "== [4] header check /vsp5 =="
  curl -fsSI "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Security-Policy-Report-Only:|^Content-Type:|^X-VSP-/{print}'
  echo "== [5] run commercial_ui_audit_v2 (tail) =="
  BASE="$BASE" bash bin/commercial_ui_audit_v2.sh | tail -n 90
  exit 0
fi

echo "== [ERR] still cannot connect -> diagnostics =="
echo "--- systemctl status ---"
sudo systemctl status "$SVC" -l --no-pager || true

echo "--- journalctl (last 120) ---"
sudo journalctl -u "$SVC" -n 120 --no-pager || true

echo "--- who listens on 8910 ---"
if command -v ss >/dev/null 2>&1; then
  ss -lntp | awk '/:8910 / || NR==1 {print}'
fi

echo "--- systemctl cat unit ---"
sudo systemctl cat "$SVC" --no-pager || true

exit 2
