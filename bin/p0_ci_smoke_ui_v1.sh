#!/usr/bin/env bash
set -euo pipefail

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TMP="${TMP_DIR:-/tmp/vsp_ci_smoke}"
mkdir -p ""
# ensure executable bit not required (CI often runs via bash anyway)

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date

fail(){ echo "[FAIL] $*"; exit 2; }
ok(){ echo "[OK] $*"; }

ts="$(date +%Y-%m-%dT%H:%M:%S%z)"
echo "== VSP UI CI SMOKE @ $ts =="
echo "[BASE] $BASE"

# 1) healthz
HZ_JSON="$TMP/healthz.json"
curl -fsS "$BASE/api/vsp/healthz" -o "$HZ_JSON" || fail "healthz unreachable"
python3 - <<PY || fail "healthz invalid json/contract"
import json
j=json.load(open("$HZ_JSON","r",encoding="utf-8"))
assert j.get("ok") is True
assert j.get("service_up") is True
assert j.get("release_status") in ("OK","STALE")
# if STALE, still allow demo/CI but warn via echo "[ARTIFACTS] "; exit 0
print("[HEALTHZ] release_status=%s pkg_exists=%s degraded=%s rid_latest=%s" % (
  j.get("release_status"), j.get("release_pkg_exists"), j.get("degraded_tools_count"), j.get("rid_latest_gate_root","")
))
PY
ok "healthz contract ok"

# 2) vsp5 html
curl -fsS -I "$BASE/vsp5" > "$TMP/vsp5.head" || fail "vsp5 unreachable"
grep -qi '^HTTP/.* 200' "$TMP/vsp5.head" || fail "vsp5 not 200"
ok "vsp5 200"

# 3) runs api
curl -fsS "$BASE/api/vsp/runs?limit=1" -o "$TMP/runs.json" || fail "runs api unreachable"
python3 - <<PY || fail "runs api not json"
import json
json.load(open("$TMP/runs.json","r",encoding="utf-8"))
print("[RUNS] ok json")
PY
ok "runs api json"

# summary line for CI logs
python3 - <<PY
import json
j=json.load(open("$HZ_JSON","r",encoding="utf-8"))
print("SMOKE_OK base=%s release=%s sha12=%s degraded=%s" % (
  "$BASE",
  j.get("release_ts",""),
  (j.get("release_sha","")[:12] if j.get("release_sha") else ""),
  j.get("degraded_tools_count",0),
))
PY

exit 0
