#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
G="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ls; need head; need cp; need date; need python3; need sudo; need systemctl; need curl

BAK="$(ls -1t ${G}.bak_extras_* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] no ${G}.bak_extras_* found"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$G" "${G}.bak_before_rb_${TS}"
echo "[BACKUP] ${G}.bak_before_rb_${TS}"

cp -f "$BAK" "$G"
echo "[OK] restored: $BAK -> $G"

python3 -m py_compile "$G"
echo "[OK] py_compile PASS"

sudo systemctl restart "$SVC" || true

# wait vsp5
for i in $(seq 1 15); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 http://127.0.0.1:8910/vsp5 2>/dev/null || true)"
  if [ "$code" = "200" ]; then echo "[OK] /vsp5=200"; exit 0; fi
  sleep 0.4
done

echo "[FAIL] still not up; show status"
systemctl status "$SVC" --no-pager || true
exit 2
