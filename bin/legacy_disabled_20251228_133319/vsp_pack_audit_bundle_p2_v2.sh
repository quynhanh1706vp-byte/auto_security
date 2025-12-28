#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
BASE="${BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== VSP AUDIT PACK P2 V2 (auto COMMERCIAL snapshot) =="

# resolve latest
J="out_ci/_latest_rid_${TS}.json"
mkdir -p out_ci
curl -sS "$BASE/api/vsp/latest_rid_v1?ts=$TS" > "$J"
RID="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("rid") or j.get("ci_rid") or "")' "$J" 2>/dev/null || true)"
RUN_DIR="$(python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j.get("ci_run_dir") or "")' "$J" 2>/dev/null || true)"
echo "[RID]=$RID"
echo "[RUN_DIR]=$RUN_DIR"

# make COMMERCIAL snapshot so pack never warns
C="out_ci/COMMERCIAL_${TS}"
mkdir -p "$C"
curl -sS "$BASE/api/vsp/dashboard_commercial_v2?ts=$TS" > "$C/dashboard_commercial_v2.json" 2>/dev/null || true
curl -sS "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=3&ts=$TS" > "$C/runs_index_3.json" 2>/dev/null || true
curl -sS "$BASE/api/vsp/findings_latest_v1?limit=10&ts=$TS" > "$C/findings_latest_10.json" 2>/dev/null || true
curl -sS "$BASE/api/vsp/rule_overrides_v1?ts=$TS" > "$C/rule_overrides.json" 2>/dev/null || true
echo "[OK] created snapshot: $C"

# now pack as usual (script will pick latest COMMERCIAL_*)
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_pack_audit_bundle_p2_v1.sh
