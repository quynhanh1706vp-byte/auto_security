#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need awk; need sed; need grep

S="/home/test/Data/SECURITY_BUNDLE/ui/bin/p1_topfind_polish_component_v1b.sh"
[ -f "$S" ] || { echo "[ERR] missing $S"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$S" "${S}.bak_testfix_${TS}"
echo "[BACKUP] ${S}.bak_testfix_${TS}"

# Keep everything up to (but excluding) the line that starts the old curl/json test
# Then append a robust test block and final DONE.
tmp="/tmp/p1_topfind_v1b_testfix.$$"
awk '
  BEGIN{cut=0}
  /^BASE="http:\/\/127\.0\.0\.1:8910"/ {cut=1}
  { if(!cut) print }
' "$S" > "$tmp"

cat >> "$tmp" <<'APPEND'

BASE="http://127.0.0.1:8910"
RID="VSP_CI_20251218_114312"

rm -f /tmp/top.h /tmp/top.b
curl -sS --max-time 5 -D /tmp/top.h -o /tmp/top.b \
  "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" || echo "CURL_EXIT=$?"

echo "== HEADERS =="; sed -n '1,15p' /tmp/top.h
echo "== BODY bytes =="; wc -c /tmp/top.b
echo "== BODY head =="; head -c 220 /tmp/top.b; echo

python3 - <<'PY'
import json, sys
b=open("/tmp/top.b","rb").read()
if not b.strip():
    print("ok= False rid_used= None total= None reason= EMPTY_BODY"); sys.exit(0)
if not b.lstrip().startswith((b"{", b"[")):
    print("ok= False rid_used= None total= None reason= NOT_JSON"); sys.exit(0)
j=json.loads(b.decode("utf-8","replace"))
print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"total=",j.get("total"),
      "limit=",j.get("limit_applied"),"trunc=",j.get("items_truncated"),
      "reason=",j.get("reason"))
if j.get("items"):
    it=j["items"][0]
    print("first_component=",it.get("component"),"ver=",it.get("version"),"title=",(it.get("title") or "")[:80])
PY

echo "[DONE]"
APPEND

mv -f "$tmp" "$S"
chmod +x "$S"
echo "[OK] patched test block in $S"

# Quick smoke: just print the last 35 lines to confirm no syntax issues
echo "== tail =="; tail -n 35 "$S"
