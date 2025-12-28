#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need awk; need wc; need sed

echo "[BASE] $BASE"

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

echo "== APIs (must ok:true) [proxy-safe urllib] =="
python3 - <<'PY'
import json, os, urllib.request, urllib.error

base=os.environ.get("VSP_UI_BASE","http://127.0.0.1:8910")

# IMPORTANT: disable env proxies for urllib (fix 404 via proxy)
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
urllib.request.install_opener(opener)

paths = [
  "/api/ui/runs_v2?limit=1",
  "/api/ui/findings_v2?limit=1&offset=0",
  "/api/ui/settings_v2",
  "/api/ui/rule_overrides_v2",
]

def fetch(p):
    url = base + p
    req = urllib.request.Request(url, headers={"Accept":"application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.status, r.read()

for p in paths:
    try:
        status, body = fetch(p)
        if status != 200:
            print("[ERR]", p, "http=", status)
            raise SystemExit(3)
        j = json.loads(body.decode("utf-8","replace"))
        ok = j.get("ok", False)
        print("[API]", p, "ok=", ok)
        if not ok:
            print("  body=", (body[:300]).decode("utf-8","replace"))
            raise SystemExit(3)
    except urllib.error.HTTPError as e:
        b = e.read() if hasattr(e, "read") else b""
        print("[ERR]", p, "HTTPError", e.code)
        print("  body=", b[:300].decode("utf-8","replace"))
        raise
print("[OK] API contract looks good")
PY

echo "[DONE] 5tabs smoke selfcheck OK"
