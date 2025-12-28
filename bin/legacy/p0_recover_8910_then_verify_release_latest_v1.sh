#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ss; need curl; need systemctl; need sed; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
WSGI="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"

echo "== [0] compile check =="
python3 - <<'PY'
import py_compile, sys
for f in ["wsgi_vsp_ui_gateway.py","vsp_demo_app.py"]:
    try:
        py_compile.compile(f, doraise=True)
        print("[OK] py_compile:", f)
    except Exception as e:
        print("[ERR] py_compile failed:", f, e)
        sys.exit(2)
PY

echo "== [1] remove stale lock (if any) =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

echo "== [2] kill any listener on :8910 (hard) =="
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910 /{print}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[INFO] killing pids: $PIDS"
  kill -9 $PIDS 2>/dev/null || true
else
  echo "[INFO] no pid bound to 8910"
fi

echo "== [3] restart via systemd =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== [4] verify port/listener =="
ss -ltnp 2>/dev/null | grep ':8910 ' || true

echo "== [5] quick HTTP sanity (/runs) =="
curl -sS -I "$BASE/runs" | sed -n '1,8p' || true

if ! curl -sS -o /dev/null "$BASE/runs"; then
  echo
  echo "== [6] systemd seems down -> show status + journal tail =="
  systemctl status "$SVC" --no-pager -l | sed -n '1,120p' || true
  journalctl -u "$SVC" -n 180 --no-pager || true

  echo
  echo "== [7] fallback start (single-owner script) =="
  if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
    bash bin/p1_ui_8910_single_owner_start_v2.sh || true
  else
    echo "[WARN] missing bin/p1_ui_8910_single_owner_start_v2.sh"
  fi
  sleep 1
  ss -ltnp 2>/dev/null | grep ':8910 ' || true
  curl -sS -I "$BASE/runs" | sed -n '1,8p' || true
fi

echo
echo "== [8] verify release_latest endpoint (should be 200 if gateway loaded block) =="
rm -f /tmp/_rel_hdr.txt /tmp/_rel_body.txt 2>/dev/null || true
curl -sS -D /tmp/_rel_hdr.txt -o /tmp/_rel_body.txt "$BASE/api/vsp/release_latest.json" || true
head -n 1 /tmp/_rel_hdr.txt | sed 's/\r$//'
echo "BODY_HEAD: $(head -c 260 /tmp/_rel_body.txt | tr '\n' ' ')"
echo

echo "[DONE]"
