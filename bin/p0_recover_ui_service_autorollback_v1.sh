#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

echo "== [0] try restart service =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 0.8

ACTIVE="$(systemctl is-active "$SVC" 2>/dev/null || true)"
echo "[INFO] $SVC is-active=$ACTIVE"

if [[ "$ACTIVE" != "active" ]]; then
  echo "== [1] SERVICE DOWN: status + last logs =="
  systemctl status "$SVC" --no-pager -l | sed -n '1,120p' || true
  echo
  journalctl -u "$SVC" -n 220 --no-pager || true
  echo

  echo "== [2] AUTO-ROLLBACK gateway from latest backup =="
  # ưu tiên backup vừa tạo: bak_staticjs_runfile_*
  BAK="$(ls -1t ${W}.bak_staticjs_runfile_* 2>/dev/null | head -n 1 || true)"
  if [[ -z "${BAK}" ]]; then
    # fallback: bất kỳ backup compile gần nhất
    BAK="$(ls -1t ${W}.bak_* 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -z "${BAK}" ]]; then
    echo "[FATAL] no backup found for $W"
    exit 2
  fi

  cp -f "$BAK" "$W"
  echo "[OK] restored: $BAK -> $W"

  echo "== [3] compile check =="
  python3 -m py_compile "$W" && echo "[OK] py_compile ok"

  echo "== [4] restart after rollback =="
  systemctl restart "$SVC" 2>/dev/null || true
  sleep 0.8
  ACTIVE2="$(systemctl is-active "$SVC" 2>/dev/null || true)"
  echo "[INFO] $SVC is-active=$ACTIVE2"

  if [[ "$ACTIVE2" != "active" ]]; then
    echo "== [5] still DOWN: status + logs =="
    systemctl status "$SVC" --no-pager -l | sed -n '1,140p' || true
    echo
    journalctl -u "$SVC" -n 260 --no-pager || true
    exit 3
  fi
fi

echo "== [6] smoke =="
curl -sS -I "$BASE/settings" | sed -n '1,12p' || true
curl -sS -I "$BASE/data_source" | sed -n '1,12p' || true
echo "[OK] service reachable"
