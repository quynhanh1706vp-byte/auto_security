#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8910}"
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
FAIL=0

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing cmd: $1"; FAIL=1; }; }
need curl; need jq; need python3

jget(){ curl -fsS "$1"; }

echo "== [1] health/version =="
jget "$BASE/healthz" | jq -e '.ok==true' >/dev/null || { echo "[FAIL] /healthz"; FAIL=1; }
jget "$BASE/api/vsp/version" | jq -e '.ok==true and (.info.git_hash|length>=1)' >/dev/null || { echo "[FAIL] /api/vsp/version"; FAIL=1; }

echo "== [2] contract: dashboard_v3 (accept by_severity at top-level OR summary_all.by_severity) =="
jget "$BASE/api/vsp/dashboard_v3" | jq -e '
  .ok==true and ( (.by_severity!=null) or (.summary_all.by_severity!=null) )
' >/dev/null || { echo "[FAIL] /api/vsp/dashboard_v3 missing by_severity (top or summary_all)"; FAIL=1; }

echo "== [3] contract: runs index resolved =="
jget "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=5&hide_empty=0&filter=1" | jq -e '.items!=null' >/dev/null \
  || { echo "[FAIL] runs_index_v3_fs_resolved"; FAIL=1; }

echo "== [4] contract: datasource/settings/rule_overrides (accept any JSON object with ok true OR any object at all) =="
jget "$BASE/api/vsp/datasource_v2?limit=10" | jq -e 'type=="object"' >/dev/null || { echo "[FAIL] datasource_v2 not JSON object"; FAIL=1; }
jget "$BASE/api/vsp/settings_v1"           | jq -e 'type=="object"' >/dev/null || { echo "[FAIL] settings_v1 not JSON object"; FAIL=1; }
jget "$BASE/api/vsp/rule_overrides_v1"     | jq -e 'type=="object"' >/dev/null || { echo "[FAIL] rule_overrides_v1 not JSON object"; FAIL=1; }

echo "== [5] latest status endpoint =="
jget "$BASE/api/vsp/run_status_latest" | jq -e 'type=="object" and (.ok==true or .ok==false)' >/dev/null \
  || { echo "[FAIL] run_status_latest not JSON"; FAIL=1; }

echo "== [6] template sanity checks =="
TPL="$ROOT/templates/vsp_dashboard_2025.html"
if [ -f "$TPL" ]; then
  dup_src="$(grep -oE '<script[^>]+src="[^"]+"' "$TPL" | sed -E 's/.*src="([^"]+)".*/\1/' | sort | uniq -d | head -n 1 || true)"
  [ -z "$dup_src" ] || { echo "[FAIL] duplicate <script src>: $dup_src"; FAIL=1; }
else
  echo "[WARN] template not found: $TPL"
fi

if [ "$FAIL" -ne 0 ]; then
  echo "[GATE] FAIL"
  exit 1
fi
echo "[GATE] PASS"
