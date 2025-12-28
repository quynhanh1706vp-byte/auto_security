#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need head; need date; need curl; need tail

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

# Restore the newest backup created by v9b script (this is the file BEFORE v9b append)
bak="$(ls -1t ${WSGI}.bak_ruleovr_v9b_* 2>/dev/null | head -n 1 || true)"
[ -n "${bak:-}" ] || err "no backup found: ${WSGI}.bak_ruleovr_v9b_*"

cp -f "$bak" "$WSGI"
ok "restored: $bak -> $WSGI"

python3 -m py_compile "$WSGI"
ok "py_compile OK"

ok "restart service"
sudo -v
if ! sudo systemctl restart "$SVC"; then
  echo "== systemctl status =="
  sudo systemctl status "$SVC" --no-pager -l || true
  echo "== journal tail =="
  sudo journalctl -xeu "$SVC" --no-pager | tail -n 180 || true
  exit 2
fi

# wait up
for i in $(seq 1 40); do
  curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1 && break
  sleep 0.25
done

echo "== [SELFTEST] GET /api/ui/rule_overrides_v2 =="
curl -fsS "$BASE/api/ui/rule_overrides_v2" | head -c 300; echo

echo "== [SELFTEST] POST /api/ui/rule_overrides_v2 =="
cat >/tmp/vsp_rule_ovr_rules.json <<'JSON'
{"rules":[{"id":"demo_disable_rule","enabled":false,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
JSON
code="$(curl -s -o /tmp/vsp_rule_ovr_put.out -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' --data-binary @/tmp/vsp_rule_ovr_rules.json \
  "$BASE/api/ui/rule_overrides_v2" || true)"
echo "POST http_code=$code"
head -c 320 /tmp/vsp_rule_ovr_put.out; echo

echo "== [FILES] =="
ls -la /home/test/Data/SECURITY_BUNDLE/ui/out_ci | grep -E 'rule_overrides_(v1\.json|audit\.log)' || true
test -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log && tail -n 3 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log || true

ok "Service is back. Hard refresh UI: $BASE/rule_overrides"
