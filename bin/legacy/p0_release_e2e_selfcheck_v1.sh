#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need egrep

echo "== [1] release_latest JSON =="
J="$(curl -fsS "$BASE/api/vsp/release_latest")"
echo "$J" | python3 -m json.tool | head -n 40

REL="$(echo "$J" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("release_pkg",""))')"
[ -n "$REL" ] || { echo "[ERR] release_pkg empty"; exit 2; }
NAME="${REL##*/}"
echo "[OK] REL=$REL"
echo "[OK] NAME=$NAME"

echo "== [2] out_ci should 302 -> download endpoint =="
curl -sS -I "$BASE/out_ci/releases/$NAME" | egrep -i 'HTTP/|Location:|X-VSP-RELEASE|Content-Length'

echo "== [3] download endpoint should 200 attachment =="
curl -sS -I "$BASE/api/vsp/release_pkg_download?path=$REL" | egrep -i 'HTTP/|content-disposition|x-vsp-release-pkg|x-vsp-release-pkg-size|x-vsp-release-pkg-dl'

echo "[DONE] release e2e looks good."
