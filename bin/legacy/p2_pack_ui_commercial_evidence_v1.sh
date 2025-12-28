#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="/tmp/vsp_ui_commercial_evidence_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

bash /home/test/Data/SECURITY_BUNDLE/ui/bin/p2_ui_state_selfcheck_v1.sh  >"$OUT/state.txt" 2>&1 || true
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/p2_ui_asset_network_smoke_v2.sh >"$OUT/smoke.txt" 2>&1 || true

curl -fsS "$BASE/api/vsp/rid_latest" >"$OUT/rid_latest.json" || true
curl -fsS "$BASE/api/ui/settings_v2" >"$OUT/settings_v2.json" || true
curl -fsS "$BASE/api/ui/rule_overrides_v2" >"$OUT/rule_overrides_v2.json" || true

tar -czf "${OUT}.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo "[OK] packed => ${OUT}.tar.gz"
