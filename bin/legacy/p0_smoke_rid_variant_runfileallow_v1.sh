#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

RID1="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
RID2="$RID1"
RID2="${RID2/VSP_CI_RUN_/VSP_CI_}"
RID2="${RID2/_RUN_/_}"

echo "RID1=$RID1"
echo "RID2=$RID2"

try_one(){
  local rid="$1"
  local path="$2"
  echo "== rid=$rid path=$path =="
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$rid&path=$path" \
  | python3 - <<'PY'
import sys, json
try:
  j=json.load(sys.stdin)
except Exception as e:
  print("[NOT_JSON]", e); sys.exit(0)
print("ok=",j.get("ok"),"degraded=",j.get("degraded"),"gate_root=",j.get("gate_root"),"rid=",j.get("rid"),"served_by=",j.get("served_by"))
PY
}

for rid in "$RID1" "$RID2"; do
  try_one "$rid" "run_gate_summary.json" || echo "[FAIL] $rid run_gate_summary.json"
  try_one "$rid" "run_gate.json"         || echo "[FAIL] $rid run_gate.json"
  try_one "$rid" "findings_unified.json" || echo "[FAIL] $rid findings_unified.json"
done
