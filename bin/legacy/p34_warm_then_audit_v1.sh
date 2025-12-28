#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need awk
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl not found"; exit 2; }

echo "== [1] restart =="
sudo systemctl restart "$SVC" || true
sudo systemctl show "$SVC" -p ActiveState -p SubState -p MainPID -p ExecMainStatus -p ExecMainCode --no-pager || true

echo "== [2] warm until selfcheck_p0 OK (retry) =="
ok=0
for i in $(seq 1 30); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/tmp/_vsp_selfcheck.json 2>/tmp/_vsp_curl.err; then
    echo "[OK] selfcheck_p0 ok (try#$i)"
    ok=1
    break
  else
    echo "[WARN] not ready (try#$i): $(tr -d '\n' </tmp/_vsp_curl.err | head -c 140)"
    sleep 0.2
  fi
done

if [ "$ok" -ne 1 ]; then
  echo "== [ERR] still cannot reach 8910 -> diagnostics =="
  sudo systemctl status "$SVC" -l --no-pager || true
  echo "--- journal (last 120) ---"
  sudo journalctl -u "$SVC" -n 120 --no-pager || true
  echo "--- listen 8910 ---"
  command -v ss >/dev/null 2>&1 && ss -lntp | awk '/:8910 / || NR==1 {print}' || true
  exit 2
fi

echo "== [3] CHECK GET header on /vsp5 (must include CSP_RO) =="
curl -fsS -D- -o /dev/null "$BASE/vsp5" \
 | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Security-Policy-Report-Only:/{print}'

echo "== [4] RUN commercial_ui_audit_v2 (tail) =="
BASE="$BASE" bash bin/commercial_ui_audit_v2.sh | tail -n 90
