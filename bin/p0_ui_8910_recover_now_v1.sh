#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TMP="/tmp/vsp_ui_recover_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TMP"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need ss
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl missing"; exit 2; }

echo "== [0] snapshot diagnostics => $TMP =="
echo "[INFO] SVC=$SVC BASE=$BASE"

echo "== [1] compile check (catch python syntax/runtime import errors early) =="
python3 -m py_compile vsp_demo_app.py wsgi_vsp_ui_gateway.py 2>"$TMP/py_compile.err" || true
if [ -s "$TMP/py_compile.err" ]; then
  echo "[ERR] py_compile failed:"
  sed -n '1,200p' "$TMP/py_compile.err"
  echo
  echo "[HINT] Restore last good backup quickly:"
  echo "  ls -1t vsp_demo_app.py.bak_* | head"
  echo "  cp -f <GOOD_BAK> vsp_demo_app.py && systemctl restart $SVC"
  exit 2
fi
echo "[OK] py_compile ok"

echo "== [2] systemd status before =="
systemctl is-active "$SVC" >"$TMP/is_active_before.txt" 2>&1 || true
systemctl status "$SVC" --no-pager >"$TMP/status_before.txt" 2>&1 || true
tail -n 40 "$TMP/status_before.txt" || true

echo "== [3] restart service (hard) =="
systemctl restart "$SVC" || true
sleep 0.2

echo "== [4] check port 8910 listen =="
ss -ltnp >"$TMP/ss.txt" 2>&1 || true
grep -n ":8910" "$TMP/ss.txt" || echo "[WARN] nothing listening on :8910"

echo "== [5] journal tail (most useful) =="
journalctl -u "$SVC" -n 120 --no-pager >"$TMP/journal_tail.txt" 2>&1 || true
tail -n 120 "$TMP/journal_tail.txt" || true

echo "== [6] if still down: fallback to single-owner start script (if exists) =="
if ! curl -fsS "$BASE/api/vsp/healthz" -o "$TMP/healthz.json" 2>"$TMP/curl.err"; then
  echo "[WARN] healthz still unreachable; trying fallback starter..."
  if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
    bash bin/p1_ui_8910_single_owner_start_v2.sh || true
  else
    echo "[WARN] missing bin/p1_ui_8910_single_owner_start_v2.sh; skipping fallback"
  fi
fi

echo "== [7] final verify =="
if curl -fsS "$BASE/api/vsp/healthz" -o "$TMP/healthz.json"; then
  echo "[OK] healthz reachable"
  python3 - <<'PY' "$TMP/healthz.json"
import json,sys
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
print("OK healthz:", "release_status=", j.get("release_status"), "rid_latest=", j.get("rid_latest_gate_root"))
PY
else
  echo "[FAIL] still cannot reach $BASE"
  echo "[ARTIFACTS] $TMP"
  echo "[NEXT] open $TMP/journal_tail.txt and paste last ~60 lines here."
  exit 2
fi

echo "[ARTIFACTS] $TMP"
echo "[DONE] UI recovered."
