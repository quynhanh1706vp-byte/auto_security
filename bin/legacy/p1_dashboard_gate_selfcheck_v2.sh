#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need awk; need sort; need mktemp; need date; need python3

tmp="$(mktemp -d /tmp/vsp_dash_gate_XXXXXX)"; trap 'rm -rf "$tmp"' EXIT
ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

echo "== [A] /vsp5 200 + anchor =="
code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/vsp5")"
echo "/vsp5 => $code"
[ "$code" = "200" ] || err "/vsp5 not 200"
curl -fsS "$BASE/vsp5" -o "$tmp/vsp5.html"
if grep -q 'id="vsp-dashboard-main"' "$tmp/vsp5.html"; then ok "anchor vsp-dashboard-main present"; else warn "anchor missing (UI may not mount correctly)"; fi

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
echo "== [C] Discover /api/vsp index (if any) =="
curl -sS "$BASE/api/vsp" -o "$tmp/apivsp.txt" || true
python3 - <<'PY'
from pathlib import Path
import json
p=Path("'$tmp'")/"apivsp.txt"
t=p.read_text(encoding="utf-8", errors="replace").strip()
print("api/vsp head:", t[:160].replace("\n"," "))
try:
    j=json.loads(t)
    keys=list(j.keys()) if isinstance(j,dict) else []
    print("api/vsp json keys:", keys[:40])
except Exception as e:
    print("api/vsp not-json:", type(e).__name__)
PY

echo
echo "== [D] Key APIs: rid_latest, runs, ui_health_v2, trend_v1, top_findings_v1 =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))' 2>/dev/null || true)"
echo "RID_latest=$RID"
if [ -z "$RID" ]; then warn "rid_latest empty"; fi

# helper: GET json + print ok + small fields
getj(){
  local url="$1"
  echo "--- $url"
  curl -sS "$BASE$url" | python3 - <<'PY'
import sys,json
raw=sys.stdin.read()
try:
    j=json.loads(raw)
    ok=j.get("ok")
    print("ok=",ok,"keys=",list(j.keys())[:12])
    # common hints
    for k in ("rid","run_id","total","count","degraded","err","points","items"):
        if k in j: 
            v=j.get(k)
            if isinstance(v,(list,dict)): 
                print(k,"type=",type(v).__name__,"len=",len(v))
            else:
                print(k,"=",v)
except Exception as e:
    print("NOT_JSON:",type(e).__name__,"head=",raw[:120].replace("\n"," "))
PY
}

getj "/api/vsp/runs?limit=1"
[ -n "$RID" ] && getj "/api/vsp/ui_health_v2?rid=$RID" || true
getj "/api/vsp/trend_v1"
getj "/api/vsp/top_findings_v1?limit=5"

echo
echo "== [E] Console error signatures in ui_8910.error.log (last 180 lines) =="
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
if [ -f "$ERRLOG" ]; then
  tail -n 180 "$ERRLOG" | grep -nE '404|Traceback|Exception|kpi api failed|trend|top_findings|dash' || echo "[OK] no obvious error signatures"
else
  warn "missing $ERRLOG"
fi

echo
echo "[DONE] If /vsp5 still shows Loading forever: paste output [D] + any console errors."
