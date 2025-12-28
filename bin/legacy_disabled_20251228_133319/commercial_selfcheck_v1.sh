#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251218_114312}"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
bad(){ echo "[FAIL] $*" >&2; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || bad "missing cmd: $1"; }
need curl; need python3; need mktemp; need head; need sed; need wc; need grep

tmp="$(mktemp -d /tmp/vsp_commcheck_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

fetch_json(){
  local url="$1" out="$2"
  local hdr="$tmp/hdr.txt" body="$tmp/body.txt"
  local code
  rm -f "$hdr" "$body" "$out" 2>/dev/null || true
  code="$(curl -sS -D "$hdr" -o "$body" -w '%{http_code}' "$url" || true)"
  if [ "$code" != "200" ] || [ ! -s "$body" ]; then
    echo "[DBG] url=$url http=$code" >&2
    echo "[DBG] headers:" >&2; sed -n '1,15p' "$hdr" >&2 || true
    echo "[DBG] body(head):" >&2; head -c 200 "$body" | sed 's/[^[:print:]\t]/?/g' >&2 || true
    return 1
  fi
  cp -f "$body" "$out"
}

echo "== [1] pages 200 =="
for p in /vsp5 /runs /releases /data_source /settings /rule_overrides; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$p" || true)"
  [ "$code" = "200" ] || bad "page $p http=$code"
done
ok "all pages 200"

echo "== [2] release_latest contract =="
RL="$tmp/release_latest.json"
fetch_json "$BASE/api/vsp/release_latest" "$RL" || bad "release_latest fetch failed"
python3 - "$RL" <<'PY'
import json,sys
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
need=["rid","download_url","audit_url"]
miss=[k for k in need if not j.get(k)]
if miss: raise SystemExit("missing keys: "+",".join(miss))
print("OK release_latest rid=", j.get("rid"))
PY
ok "release_latest keys present"

echo "== [3] releases presence (HTML-first) =="
HTML="$tmp/releases.html"
curl -fsS "$BASE/releases" -o "$HTML" || bad "/releases fetch failed"
n="$(grep -c 'release_download?rid=' "$HTML" || true)"
if [ "${n:-0}" -lt 1 ]; then
  bad "no releases found on /releases (n=$n)"
fi
ok "releases found on /releases (n=$n)"

echo "== [3b] optional /api/vsp/releases =="
API="$tmp/releases_api.json"
if fetch_json "$BASE/api/vsp/releases" "$API"; then
  ok "/api/vsp/releases reachable"
else
  warn "/api/vsp/releases not reachable (likely allowlist). OK for commercial if /releases works."
fi

echo "== [4] download + audit for RID =="
curl -fSL "$BASE/api/vsp/release_download?rid=$RID" -o "$tmp/release.zip" || bad "download failed rid=$RID"
[ -s "$tmp/release.zip" ] || bad "download empty rid=$RID"
ok "download OK rid=$RID size=$(wc -c <"$tmp/release.zip")"

AJ="$tmp/audit.json"
fetch_json "$BASE/api/vsp/release_audit?rid=$RID" "$AJ" || bad "audit fetch failed rid=$RID"
python3 - "$AJ" "$RID" <<'PY'
import json,sys
p,rid=sys.argv[1],sys.argv[2]
j=json.load(open(p,"r",encoding="utf-8"))
assert j.get("ok") is True, "audit ok!=true"
assert j.get("rid")==rid, f"rid mismatch: {j.get('rid')}"
for k in ("package_sha256","package_path","manifest_path","download_url","audit_url"):
  assert j.get(k), f"missing {k}"
print("OK audit rid=", j.get("rid"))
PY
ok "audit OK rid=$RID"

echo "[PASS] COMMERCIAL SELF-CHECK OK (RID=$RID BASE=$BASE)"
