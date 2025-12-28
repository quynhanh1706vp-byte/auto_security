#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE_IPV4="http://127.0.0.1:8910"
LOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/warm_cache.log"
DROP="/etc/systemd/system/${SVC}.d/40-warm-cache.conf"
WARM_BIN="/usr/local/bin/vsp_warm_cache.sh"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need python3; need curl; need bash

sudo mkdir -p /home/test/Data/SECURITY_BUNDLE/ui/out_ci
sudo chmod 775 /home/test/Data/SECURITY_BUNDLE/ui/out_ci || true

# 1) Write warm script reliably (avoid heredoc paste corruption)
python3 - <<'PY'
from pathlib import Path
content = r"""#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://127.0.0.1:8910}"
LOG="${2:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/warm_cache.log}"

mkdir -p "$(dirname "$LOG")"
# Always create log early
: >"$LOG" || true

exec >>"$LOG" 2>&1
echo "== warm_cache start $(date -Is) BASE=$BASE =="

# Wait until selfcheck ok
for i in $(seq 1 160); do
  if curl -fsS -o /dev/null --connect-timeout 1 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    echo "[OK] selfcheck_p0 ready at try=$i"
    break
  fi
  sleep 0.25
done

# Warm /vsp5 multiple times to hit BOTH gunicorn workers (RAM not shared).
# With 2 workers, 8-12 calls usually enough.
for n in $(seq 1 12); do
  hdr="$(curl -sS -D- -o /dev/null -w " time_total=%{time_total}\n" --connect-timeout 1 --max-time 25 "$BASE/vsp5" \
      | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^ time_total=/ {print}' || true)"
  echo "[WARM] /vsp5 call#$n"
  echo "$hdr"
done

echo "== warm_cache end $(date -Is) =="
"""
Path("/tmp/vsp_warm_cache.sh").write_text(content, encoding="utf-8")
print("[OK] wrote /tmp/vsp_warm_cache.sh")
PY

sudo cp -f /tmp/vsp_warm_cache.sh "$WARM_BIN"
sudo chmod +x "$WARM_BIN"

# 2) Install drop-in: run warm in background (don’t block startup)
sudo mkdir -p "/etc/systemd/system/${SVC}.d"
sudo tee "$DROP" >/dev/null <<EOF
[Service]
ExecStartPost=/bin/bash -lc 'nohup ${WARM_BIN} ${BASE_IPV4} ${LOG} >/dev/null 2>&1 &'
EOF

echo "[OK] drop-in => $DROP"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

# 3) Wait a bit for warm to run, then show status + log
sleep 2
echo "== [STATUS] =="
sudo systemctl --no-pager --full status "$SVC" | head -n 18 || true

echo "== [LOG exists?] =="
if [ -f "$LOG" ]; then
  ls -l "$LOG"
  echo "== [TAIL warm_cache.log] =="
  tail -n 40 "$LOG" || true
else
  echo "[WARN] warm_cache.log missing"
  echo "== [journal tail] =="
  sudo journalctl -u "$SVC" --no-pager -n 40 || true
  echo "== [manual run warm once] =="
  bash "$WARM_BIN" "$BASE_IPV4" "$LOG" || true
  tail -n 40 "$LOG" || true
fi

# 4) Smoke: 4 calls to show mixed HIT-DISK/HIT-RAM across 2 workers
echo "== [SMOKE] 4 sequential /vsp5 calls =="
for n in 1 2 3 4; do
  echo "-- call#$n --"
  curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "$BASE_IPV4/vsp5" \
    | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
done
