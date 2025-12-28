#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
DROP="/etc/systemd/system/${SVC}.d/40-warm-cache.conf"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need systemctl; need bash; need curl

tmp="$(mktemp -d /tmp/vsp_warmcache_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/warm_cache.sh" <<'WARM'
#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-http://127.0.0.1:8910}"

# wait selfcheck
for i in $(seq 1 80); do
  if curl -fsS -o /dev/null --connect-timeout 1 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

# pick latest rid (best-effort)
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
)"

# warm no-rid (LATEST)
curl -fsS -o /dev/null --connect-timeout 1 --max-time 20 "$BASE/vsp5" || true
curl -fsS -o /dev/null --connect-timeout 1 --max-time 20 "$BASE/vsp5" || true

# warm explicit rid if available
if [ -n "${RID:-}" ]; then
  curl -fsS -o /dev/null --connect-timeout 1 --max-time 20 "$BASE/vsp5?rid=$RID" || true
  curl -fsS -o /dev/null --connect-timeout 1 --max-time 20 "$BASE/vsp5?rid=$RID" || true
fi

# warm heavy API cache too (optional, safe)
if [ -n "${RID:-}" ]; then
  curl -fsS -o /dev/null --connect-timeout 1 --max-time 30 "$BASE/api/vsp/findings_unified_v1/$RID" || true
  curl -fsS -o /dev/null --connect-timeout 1 --max-time 30 "$BASE/api/vsp/findings_unified_v1/$RID" || true
fi
WARM

chmod +x "$tmp/warm_cache.sh"

sudo mkdir -p "/etc/systemd/system/${SVC}.d"
sudo cp -f "$tmp/warm_cache.sh" "/usr/local/bin/vsp_warm_cache.sh"
sudo chmod +x "/usr/local/bin/vsp_warm_cache.sh"

sudo tee "$DROP" >/dev/null <<EOF
[Service]
# P33: warm cache after start (non-blocking; keep it short)
ExecStartPost=/bin/bash -lc '/usr/local/bin/vsp_warm_cache.sh ${BASE}'
EOF

echo "[OK] wrote $DROP"
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"

echo "== [STATUS] =="
sudo systemctl --no-pager --full status "$SVC" | head -n 18 || true

echo "== [SMOKE] first open should be fast =="
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
