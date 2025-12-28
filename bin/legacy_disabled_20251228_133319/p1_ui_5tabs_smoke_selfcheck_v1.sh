#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need sed; need grep; need awk; need wc

echo "[BASE] $BASE"

head_len(){
  local path="$1"
  curl -fsS -I "$BASE$path" | awk -F': ' 'tolower($1)=="content-length"{print $2}' | tr -d '\r'
}

must_200(){
  local path="$1"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$path")"
  if [[ "$code" != "200" && "$code" != "302" ]]; then
    echo "[ERR] $path http=$code"
    exit 2
  fi
  echo "[OK] $path http=$code"
}

must_nonzero(){
  local path="$1"
  local n
  n="$(curl -fsS "$BASE$path" | wc -c | tr -d ' ')"
  if [[ "${n:-0}" -lt 400 ]]; then
    echo "[ERR] $path body too small: $n"
    exit 2
  fi
  echo "[OK] $path bytes=$n"
}

echo "== UI pages =="
must_200 "/"
must_200 "/vsp5"
must_200 "/runs"
must_200 "/data_source"
must_200 "/settings"
must_200 "/rule_overrides"

echo "== UI bodies (non-zero) =="
must_nonzero "/vsp5"
must_nonzero "/runs"
must_nonzero "/data_source"
must_nonzero "/settings"
must_nonzero "/rule_overrides"

echo "== APIs (must ok:true) =="
python3 - <<'PY'
import json, urllib.request, os
base=os.environ.get("VSP_UI_BASE","http://127.0.0.1:8910")
def get(p):
    with urllib.request.urlopen(base+p) as r:
        return json.loads(r.read().decode("utf-8","replace"))
for p in [
  "/api/ui/runs_v2?limit=1",
  "/api/ui/findings_v2?limit=1&offset=0",
  "/api/ui/settings_v2",
  "/api/ui/rule_overrides_v2",
]:
    j=get(p)
    ok=j.get("ok",False)
    print("[API]",p,"ok=",ok)
    if not ok: raise SystemExit(3)
    if "counts" in j and isinstance(j["counts"],dict):
        print("  TOTAL=", j["counts"].get("TOTAL"))
    if "items" in j and isinstance(j["items"],list) and j["items"]:
        print("  first_rid=", j["items"][0].get("rid"))
print("[OK] API contract looks good")
PY

echo "== Content-Length (debug) =="
for p in /runs /data_source /settings /rule_overrides; do
  echo "$p CL=$(head_len "$p")"
done
echo "[DONE] 5tabs smoke selfcheck OK"
