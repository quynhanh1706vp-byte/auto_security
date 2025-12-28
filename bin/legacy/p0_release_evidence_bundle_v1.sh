#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need mkdir; need cp; need tar; need sha256sum; need curl

TS="$(date +%Y%m%d_%H%M%S)"
E="out_ci/evidence/EVID_${TS}"
mkdir -p "$E"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [A] capture gate output =="
bash bin/p0_commercial_release_gate_selfcheck_v1.sh | tee "$E/gate_output.txt" || true

echo "== [B] capture key endpoints =="
for p in "/api/vsp/rid_latest" "/api/vsp/release_latest" "/api/vsp/top_findings_v1?limit=5"; do
  fn="$(echo "$p" | tr '/?&=' '_' )"
  curl -sS --max-time 8 "$BASE$p" > "$E/${fn}.json" || true
done

echo "== [C] copy logs if present =="
cp -f out_ci/ui_8910.error.log "$E/" 2>/dev/null || true
cp -f out_ci/ui_8910.access.log "$E/" 2>/dev/null || true

echo "== [D] config pointers =="
cp -f /etc/systemd/system/vsp-ui-8910.service "$E/" 2>/dev/null || true
cp -rf /etc/systemd/system/vsp-ui-8910.service.d "$E/" 2>/dev/null || true

echo "== [E] tar evidence =="
PKG="out_ci/releases/VSP_UI_EVIDENCE_${TS}.tgz"
tar -czf "$PKG" -C out_ci/evidence "EVID_${TS}"
sha256sum "$PKG" | tee "$PKG.sha256"

echo "[DONE] $PKG"
