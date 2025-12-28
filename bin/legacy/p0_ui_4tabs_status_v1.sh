#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need sed; need wc; need egrep
command -v systemctl >/dev/null 2>&1 || true
command -v journalctl >/dev/null 2>&1 || true

h(){ echo; echo "==================== $* ===================="; }

tab(){
  local path="$1"
  h "TAB $path (HEAD)"
  curl -sS -I "$BASE$path" | sed -n '1,12p' || true
  h "TAB $path (BODY bytes)"
  curl -sS "$BASE$path" -o /tmp/vsp_tab_body.$$ || true
  wc -c /tmp/vsp_tab_body.$$ || true
  rm -f /tmp/vsp_tab_body.$$ || true
}

api(){
  local path="$1"
  h "API $path"
  curl -fsS "$BASE$path" | head -c 900; echo
}

h "SERVICE LISTEN"
( command -v ss >/dev/null 2>&1 && ss -ltnp | egrep ':8910|LISTEN' ) || true

h "HEALTHZ (best effort)"
curl -fsS "$BASE/api/vsp/healthz" 2>/dev/null || curl -fsS "$BASE/healthz" 2>/dev/null || echo "[WARN] no healthz endpoint"

tab "/vsp5"
tab "/runs"
tab "/data_source"
tab "/settings"

api "/api/vsp/runs?limit=1"
api "/api/vsp/release_latest"

h "RELEASE E2E (redirect + download headers)"
J="$(curl -fsS "$BASE/api/vsp/release_latest")"
REL="$(echo "$J" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("release_pkg",""))')"
if [ -n "$REL" ]; then
  NAME="${REL##*/}"
  echo "[OK] REL=$REL"
  echo "[OK] NAME=$NAME"
  echo "-- HEAD /out_ci/releases/$NAME --"
  curl -sS -I "$BASE/out_ci/releases/$NAME" | egrep -i 'HTTP/|Location:|X-VSP-RELEASE|Content-Length' || true
  echo "-- HEAD /api/vsp/release_pkg_download?path=REL --"
  curl -sS -I "$BASE/api/vsp/release_pkg_download?path=$REL" | egrep -i 'HTTP/|content-disposition|x-vsp-release-pkg|x-vsp-release-pkg-size|x-vsp-release-pkg-dl' || true
else
  echo "[WARN] release_pkg empty"
fi

h "TAIL LOG (journalctl -u $SVC -n 120)"
( command -v journalctl >/dev/null 2>&1 && journalctl -u "$SVC" -n 120 --no-pager ) || echo "[WARN] journalctl not available"

echo
echo "[DONE] 4-tabs + api + logs checked."
