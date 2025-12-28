#!/usr/bin/env bash
set -euo pipefail
PORT=8910
BASE_LOOP="http://127.0.0.1:${PORT}"
BASE_LOCALHOST="http://localhost:${PORT}"
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
BASE_IP=""
[ -n "${IP:-}" ] && BASE_IP="http://${IP}:${PORT}"

echo "== [1] loopback state =="
ip -br link show lo || true
ip -br addr show lo || true
echo

echo "== [2] route sanity =="
ip route get 127.0.0.1 2>/dev/null || true
echo

echo "== [3] listeners =="
ss -lptn "sport = :${PORT}" || true
echo

echo "== [4] try connect via python socket (bypass curl) =="
python3 - <<PY
import socket
for host in ["127.0.0.1","localhost","$IP"]:
    if not host or host=="None": 
        continue
    try:
        s=socket.create_connection((host, $PORT), timeout=2)
        print("[OK] socket connect", host, $PORT)
        s.close()
    except Exception as e:
        print("[FAIL] socket connect", host, $PORT, type(e).__name__, e)
PY
echo

echo "== [5] curl verbose (soi refused vs reset vs timeout) =="
set +e
curl -v --connect-timeout 2 --max-time 4 "$BASE_LOOP/api/vsp/rid_latest" -o /tmp/rid_loop.json
echo "[rc]=$?"
echo
curl -v --connect-timeout 2 --max-time 4 "$BASE_LOCALHOST/api/vsp/rid_latest" -o /tmp/rid_localhost.json
echo "[rc]=$?"
echo
if [ -n "$BASE_IP" ]; then
  curl -v --connect-timeout 2 --max-time 4 "$BASE_IP/api/vsp/rid_latest" -o /tmp/rid_ip.json
  echo "[rc]=$?"
fi
set -e
echo

echo "== [6] proxy env (nhiều máy bị proxy/no_proxy làm trò) =="
env | grep -iE 'http_proxy|https_proxy|no_proxy' || echo "(no proxy env)"
echo

echo "== [7] firewall quick grep port 8910 =="
if command -v sudo >/dev/null 2>&1; then
  sudo iptables -S 2>/dev/null | grep -E "8910|lo" | head -n 80 || true
  sudo nft list ruleset 2>/dev/null | grep -nE "8910|loopback|127\.0\.0\.1" | head -n 80 || true
fi

echo "[DONE] v26t"
