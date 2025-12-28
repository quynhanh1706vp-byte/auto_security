#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1' | jq -er '.items[0].run_id')"
echo "[RID] $RID"

CI="$(curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq -r '.ci_run_dir // empty')"
[ -n "$CI" ] || { echo "[ERR] cannot resolve ci_run_dir"; exit 2; }
echo "[CI] $CI"

F1="$CI/findings_unified.json"
F2="$CI/reports/findings_unified.json"

count_json () {
  python3 - "$1" <<'PY'
import json,sys,os
p=sys.argv[1]
if not os.path.exists(p):
  print(-1); raise SystemExit(0)
j=json.load(open(p,"r",encoding="utf-8"))
if isinstance(j,list):
  print(len(j)); raise SystemExit(0)
if isinstance(j,dict):
  if isinstance(j.get("items"),list):
    print(len(j["items"])); raise SystemExit(0)
  if isinstance(j.get("findings"),list):
    print(len(j["findings"])); raise SystemExit(0)
  if isinstance(j.get("results"),list):
    print(len(j["results"])); raise SystemExit(0)
print(0)
PY
}

N1="$(count_json "$F1")"
N2="$(count_json "$F2")"
echo "[COUNT] root=$N1 file=$F1"
echo "[COUNT] reports=$N2 file=$F2"

if [ "$N2" -gt 0 ] && { [ "$N1" -eq -1 ] || [ "$N1" -eq 0 ]; }; then
  echo "[FIX] copy reports -> root (canonical findings_unified.json)"
  cp -f "$F2" "$F1"
else
  echo "[OK] no copy needed"
fi

N1B="$(count_json "$F1")"
echo "[RECHECK] root_now=$N1B"
