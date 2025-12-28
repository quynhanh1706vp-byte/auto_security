#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need awk; need sort; need mktemp; need date; need python3

tmp="$(mktemp -d /tmp/vsp_dash_gate_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
export VSP_TMP_DIR="$tmp"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

echo "== [A] /vsp5 200 + anchor =="
code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/vsp5")"
echo "/vsp5 => $code"
[ "$code" = "200" ] || err "/vsp5 not 200"
curl -fsS "$BASE/vsp5" -o "$tmp/vsp5.html"
if grep -q 'id="vsp-dashboard-main"' "$tmp/vsp5.html"; then ok "anchor vsp-dashboard-main present"; else warn "anchor missing"; fi

echo
echo "== [B] JS urls on /vsp5 all 200/304 =="
grep -hoE 'src="/static/[^"]+\.js[^"]*"' "$tmp/vsp5.html" | sed 's/^src="//; s/"$//' | sort -u > "$tmp/js.list" || true
echo "js_count=$(wc -l <"$tmp/js.list" | tr -d ' ')"
bad=0
while read -r u; do
  [ -n "$u" ] || continue
  c="$(curl -s -o /dev/null -w '%{http_code}' "$BASE$u")"
  if [ "$c" != "200" ] && [ "$c" != "304" ]; then
    echo "[BAD] $c $u"
    bad=1
  fi
done < "$tmp/js.list"
[ "$bad" -eq 0 ] && ok "all js 200/304" || warn "some js not 200/304"

echo
echo "== [C] /api/vsp index (best effort) =="
curl -sS "$BASE/api/vsp" -o "$tmp/apivsp.txt" || true
python3 - <<'PY'
import os, json
from pathlib import Path
p = Path(os.environ["VSP_TMP_DIR"]) / "apivsp.txt"
t = p.read_text(encoding="utf-8", errors="replace").strip()
print("api/vsp head:", t[:180].replace("\n"," "))
try:
    j=json.loads(t)
    if isinstance(j, dict):
        print("api/vsp json keys:", list(j.keys())[:40])
    else:
        print("api/vsp json type:", type(j).__name__)
except Exception as e:
    print("api/vsp not-json:", type(e).__name__)
PY

echo
echo "== [D] Key APIs: rid_latest, runs, ui_health_v2, trend_v1, top_findings_v1 =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))' 2>/dev/null || true)"
echo "RID_latest=$RID"
[ -n "$RID" ] || warn "rid_latest empty"

getj(){
  local url="$1"
  echo "--- $url"
  curl -sS "$BASE$url" | python3 - <<'PY'
import sys,json
raw=sys.stdin.read()
try:
    j=json.loads(raw)
    print("ok=",j.get("ok"),"keys=",list(j.keys())[:14])
    for k in ("rid","run_id","total","count","degraded","err"):
        if k in j: print(k,"=",j.get(k))
    for k in ("points","items","runs"):
        if k in j:
            v=j.get(k)
            if isinstance(v,list): print(k,"len=",len(v))
            elif isinstance(v,dict): print(k,"keys=",list(v.keys())[:10])
            else: print(k,"type=",type(v).__name__)
except Exception as e:
    print("NOT_JSON:",type(e).__name__,"head=",raw[:120].replace("\n"," "))
PY
}

getj "/api/vsp/runs?limit=1"
[ -n "$RID" ] && getj "/api/vsp/ui_health_v2?rid=$RID" || true
getj "/api/vsp/trend_v1"
getj "/api/vsp/top_findings_v1?limit=5"

echo
echo "== [E] Error signatures in ui_8910.error.log (tail) =="
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
if [ -f "$ERRLOG" ]; then
  tail -n 220 "$ERRLOG" | grep -nE '404|Traceback|Exception|kpi api failed|trend_v1|top_findings_v1|DASH|dash' \
    || echo "[OK] no obvious error signatures"
else
  warn "missing $ERRLOG"
fi

echo
echo "[DONE] If trend/top empty but ok=true, UI should still show degraded fallback."
