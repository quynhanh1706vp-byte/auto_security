#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"

echo "== [P62 RESCUE] =="
echo "[INFO] SVC=$SVC BASE=$BASE APP=$APP"

latest_bak="$(ls -1t ${APP}.bak_p62_* 2>/dev/null | head -n 1 || true)"
echo "[INFO] latest_bak=${latest_bak:-NONE}"

echo "== [1] py_compile current app =="
if python3 -m py_compile "$APP" 2>out_ci/p62_pycompile.err; then
  echo "[OK] py_compile OK"
else
  echo "[ERR] py_compile FAILED -> showing error:"
  sed -n '1,180p' out_ci/p62_pycompile.err || true
  if [ -n "${latest_bak:-}" ] && [ -f "$latest_bak" ]; then
    echo "== [ROLLBACK] restore from $latest_bak =="
    cp -f "$latest_bak" "$APP"
    python3 -m py_compile "$APP" && echo "[OK] rollback py_compile OK"
  else
    echo "[FATAL] no backup to rollback"; exit 2
  fi
fi

echo "== [2] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  echo "== systemctl status (tail) =="
  systemctl status "$SVC" --no-pager | tail -n 60 || true
  echo "== journalctl (tail) =="
  sudo journalctl -u "$SVC" -n 120 --no-pager || true
else
  echo "[WARN] systemctl not found, skip service restart"
fi

echo "== [3] wait port up =="
ok=0
for i in $(seq 1 30); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/vsp5" || true)"
  if [ "$code" = "200" ]; then ok=1; echo "[OK] /vsp5 200 on try#$i"; break; fi
  sleep 0.2
done
if [ "$ok" -ne 1 ]; then
  echo "[ERR] UI still not up on $BASE (try curl $BASE/vsp5)"
  exit 0
fi

echo "== [4] verify api =="
curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" | head -c 400; echo
echo "[DONE]"
