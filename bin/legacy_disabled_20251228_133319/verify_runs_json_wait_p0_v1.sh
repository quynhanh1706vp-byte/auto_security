#!/usr/bin/env bash
set -euo pipefail

HOST=127.0.0.1
PORT=8910
URL="http://${HOST}:${PORT}/api/vsp/runs?limit=1"
SVC="vsp-ui-8910.service"
UI="/home/test/Data/SECURITY_BUNDLE/ui"
ERR="${UI}/out_ci/ui_8910.error.log"

echo "== wait LISTEN ${HOST}:${PORT} (max ~8s) =="
for i in $(seq 1 40); do
  if ss -ltnp 2>/dev/null | grep -q "${HOST}:${PORT}"; then
    echo "[OK] LISTEN try=$i"
    break
  fi
  sleep 0.2
done

echo "== wait /api/vsp/runs returns JSON (max ~10s) =="
HDR="$(mktemp)"; BODY="$(mktemp)"
ok=0
for i in $(seq 1 50); do
  : >"$HDR"; : >"$BODY"
  set +e
  curl -sS -D "$HDR" -o "$BODY" "$URL"
  rc=$?
  set -e
  ct="$(grep -i '^content-type:' "$HDR" | head -n1 | tr -d '\r' || true)"
  if [ $rc -eq 0 ] && echo "$ct" | grep -qi 'application/json' && [ -s "$BODY" ]; then
    ok=1
    echo "[OK] JSON try=$i"
    break
  fi
  sleep 0.2
done

if [ $ok -ne 1 ]; then
  echo "[FAIL] /api/vsp/runs not ready/json"
  echo "--- status line ---"; sed -n '1p' "$HDR" || true
  echo "--- content-type ---"; grep -i '^content-type:' "$HDR" || true
  echo "--- first 200 bytes body ---"
  python3 - <<PY
b=open("$BODY","rb").read(200)
print(b.decode("utf-8","replace"))
PY
  echo "== systemctl status =="; sudo systemctl --no-pager --full status "$SVC" | sed -n '1,80p' || true
  echo "== tail error log =="; test -f "$ERR" && tail -n 160 "$ERR" || true
  rm -f "$HDR" "$BODY"
  exit 2
fi

echo "--- status line ---"; sed -n '1p' "$HDR"
echo "--- x-vsp-runs-has ---"; grep -i '^x-vsp-runs-has:' "$HDR" || true

python3 - <<PY
import json
d=json.load(open("$BODY","r",encoding="utf-8",errors="replace"))
it=(d.get("items") or [{}])[0]
print("run_id=", it.get("run_id"))
print("has=", it.get("has"))
PY

rm -f "$HDR" "$BODY"
