#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need awk; need tr; need date

# 1) read X-VSP-RELEASE-TS from headers (stable per release)
rel_ts="$(curl -sSI "$BASE/vsp5" | awk -F': ' 'tolower($1)=="x-vsp-release-ts"{print $2}' | tr -d '\r' | tail -n 1)"
if [ -z "${rel_ts:-}" ]; then
  rel_ts="$(date +%Y%m%d_%H%M%S)"
  echo "[WARN] cannot read X-VSP-RELEASE-TS; fallback rel_ts=$rel_ts"
else
  echo "[OK] detected X-VSP-RELEASE-TS=$rel_ts"
fi

# 2) pin env in service drop-in (persistent)
if command -v systemctl >/dev/null 2>&1; then
  sudo mkdir -p "/etc/systemd/system/${SVC}.d"
  sudo tee "/etc/systemd/system/${SVC}.d/p2_asset_v_pin.conf" >/dev/null <<EOF
[Service]
Environment=VSP_ASSET_V=${rel_ts}
Environment=VSP_RELEASE_TS=${rel_ts}
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

  echo "== systemd env snippet =="
  sudo systemctl show "$SVC" -p Environment --no-pager | sed 's/^/[ENV] /'
else
  echo "[ERR] systemctl not found; cannot pin service env"
  exit 2
fi

# 3) verify via API (meta.asset_v should be rel_ts now)
echo "== verify ui_health_v2 meta.asset_v =="
curl -sS "$BASE/api/vsp/ui_health_v2" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "marker=", j.get("marker"))
print("meta.asset_v=", (j.get("meta") or {}).get("asset_v"))
PY

# 4) verify all tabs now share same v=
echo "== verify v= across tabs (should be ONE value) =="
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  echo "-- $p --"
  curl -sS "$BASE$p" | grep -oE 'v=[0-9_]+' | head -n 20 || true
done

echo "== unique v values =="
( for p in "${tabs[@]}"; do curl -sS "$BASE$p" | grep -oE 'v=[0-9_]+' || true; done ) \
  | sed 's/^v=//' | sort -u | sed 's/^/[V] /'
