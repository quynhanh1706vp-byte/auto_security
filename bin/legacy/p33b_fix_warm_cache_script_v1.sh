#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
DROP="/etc/systemd/system/${SVC}.d/40-warm-cache.conf"
LOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/warm_cache.log"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need bash; need curl; need python3

# hard-force IPv4 base for warm (avoid ::/localhost surprises)
BASE_IPV4="http://127.0.0.1:8910"

sudo tee /usr/local/bin/vsp_warm_cache.sh >/dev/null <<'WARM'
#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://127.0.0.1:8910}"
LOG="${2:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/warm_cache.log}"
mkdir -p "$(dirname "$LOG")"

exec >>"$LOG" 2>&1
echo "== warm_cache start $(date -Is) BASE=$BASE =="

# Wait until TCP accept + selfcheck OK
for i in $(seq 1 120); do
  if curl -fsS -o /dev/null --connect-timeout 1 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    echo "[OK] selfcheck_p0 ready at try=$i"
    break
  fi
  sleep 0.25
done

# Warm /vsp5 (no rid) twice: call#1 builds cache, call#2 ensures HIT-RAM
for n in 1 2; do
  t="$(curl -sS -D- -o /dev/null -w "%{time_total}" --connect-timeout 1 --max-time 25 "$BASE/vsp5" \
      | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:/ {print} END{ }' ; true)"
  echo "[WARM] /vsp5 call#$n done"
done

# Warm latest rid if endpoint exists (optional)
RID="$(curl -fsS --connect-timeout 1 --max-time 8 "$BASE/api/vsp/latest_rid_v1" 2>/dev/null \
  | python3 - <<'PY'
import sys, json
try:
  j=json.load(sys.stdin)
except Exception:
  print(""); raise SystemExit(0)
for k in ("rid","run_id","latest_rid"):
  v=j.get(k)
  if isinstance(v,str) and v.strip():
    print(v.strip()); raise SystemExit(0)
print("")
PY
)" || true

if [ -n "${RID:-}" ]; then
  for n in 1 2; do
    curl -fsS -o /dev/null --connect-timeout 1 --max-time 25 "$BASE/vsp5?rid=$RID" || true
  done
  for n in 1 2; do
    curl -fsS -o /dev/null --connect-timeout 1 --max-time 40 "$BASE/api/vsp/findings_unified_v1/$RID" || true
  done
fi

echo "== warm_cache end $(date -Is) =="
WARM

sudo chmod +x /usr/local/bin/vsp_warm_cache.sh

sudo mkdir -p "/etc/systemd/system/${SVC}.d"
sudo tee "$DROP" >/dev/null <<EOF
[Service]
# P33b: warm cache in background + log (do not block startup)
ExecStartPost=/bin/bash -lc 'nohup /usr/local/bin/vsp_warm_cache.sh ${BASE_IPV4} ${LOG} >/dev/null 2>&1 &'
EOF

echo "[OK] updated warm-cache drop-in: $DROP"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "== [STATUS] =="
sudo systemctl --no-pager --full status "$SVC" | head -n 18 || true

echo "== [TAIL warm_cache.log] =="
sleep 1
tail -n 40 "$LOG" || true

echo "== [SMOKE] open /vsp5 twice =="
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "${BASE_IPV4}/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "${BASE_IPV4}/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
