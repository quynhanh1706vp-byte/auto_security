#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need date; need mktemp

F="bin/p0_commercial_final_selfcheck_v1.sh"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_rebuild_${TS}" 2>/dev/null || true
echo "[BACKUP] ${F}.bak_rebuild_${TS}"

cat > "$F" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need mktemp

OK=0; WARN=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*" >&2; WARN=$((WARN+1)); }
err(){ echo "[ERR] $*" >&2; ERR=$((ERR+1)); }

RID_A="${1:-VSP_CI_20251219_092640}"
RID_B="${2:-VSP_CI_20251218_113514}"

tmp="$(mktemp -d /tmp/vsp_selfcheck_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "== [0] pages reachable =="
pages=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${pages[@]}"; do
  if curl -fsS --compressed "$BASE$p" >/dev/null; then ok "page $p"; else err "page $p"; fi
done

echo "== [1] JS markers present =="
J1="$BASE/static/js/vsp_dashboard_consistency_patch_v1.js"
J2="$BASE/static/js/vsp_dashboard_luxe_v1.js"
curl -fsS "$J1" | grep -q "VSP_P0_FINDINGS_MISSING_BANNER_V1" && ok "marker findings banner" || err "missing marker findings banner"
curl -fsS "$J2" | grep -q "VSP_P0_DEGRADED_RID_GUARD_V2" && ok "marker rid guard v2" || err "missing marker rid guard v2"
curl -fsS "$J2" | grep -q "VSP_P0_SILENCE_DEGRADED_LOG_V2" && ok "marker silence log v2" || warn "silence log v2 not found (optional)"

echo "== [2] script tags in /vsp5 html =="
curl -fsS --compressed "$BASE/vsp5?rid=$RID_A" | grep -q "vsp_dashboard_luxe_v1.js" && ok "luxe js on RID_A" || err "luxe js missing on RID_A"
curl -fsS --compressed "$BASE/vsp5?rid=$RID_B" | grep -q "vsp_dashboard_consistency_patch_v1.js" && ok "consistency js on RID_B" || err "consistency js missing on RID_B"

echo "== [3] API contract sanity =="
# rid_latest must be JSON
curl -fsS "$BASE/api/vsp/rid_latest" -o "$tmp/rid_latest.json" || err "rid_latest request failed"
python3 - "$tmp/rid_latest.json" <<'PY' || err "rid_latest bad json"
import json,sys
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))
assert isinstance(j,dict)
print("[OK] rid_latest =>", j.get("rid"))
PY

# counts_total + findings len via run_file_allow
python3 - "$BASE" "$RID_A" "$RID_B" <<'PY' || err "gate/findings sanity failed"
import json, sys, subprocess, urllib.parse
BASE, RA, RB = sys.argv[1], sys.argv[2], sys.argv[3]
paths=["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"]

def getj(url):
    out = subprocess.check_output(["curl","-fsS","-L",url], timeout=8)
    return json.loads(out.decode("utf-8","replace"))

def gate(rid):
    for p in paths:
        u=f"{BASE}/api/vsp/run_file_allow?rid={urllib.parse.quote(rid)}&path={urllib.parse.quote(p)}"
        try:
            j=getj(u)
            if isinstance(j,dict) and (j.get("counts_total") or j.get("by_tool") or ("ok" in j)):
                return j
        except Exception:
            pass
    return None

def findings_len(rid):
    u=f"{BASE}/api/vsp/run_file_allow?rid={urllib.parse.quote(rid)}&path=findings_unified.json&limit=5"
    try:
        j=getj(u)
    except Exception:
        return None
    if isinstance(j,dict) and isinstance(j.get("findings"), list):
        return len(j["findings"])
    return None

def sum_counts(ct):
    if not isinstance(ct,dict): return 0
    s=0
    for _,v in ct.items():
        if isinstance(v,(int,float)): s += v
        elif isinstance(v,dict):
            for _,vv in v.items():
                if isinstance(vv,(int,float)): s += vv
    return s

for rid in (RA,RB):
    g = gate(rid)
    if not g:
        print("[ERR] gate missing for", rid)
        continue
    ct = g.get("counts_total") or {}
    s = sum_counts(ct)
    fl = findings_len(rid)
    print("[OK] rid=", rid, "counts_total_sum=", s, "findings_len=", fl)
PY

echo "== [4] summary =="
echo "OK=$OK WARN=$WARN ERR=$ERR"
if [ "$ERR" -eq 0 ]; then
  echo "VERDICT: PASS (P0 commercial UI selfcheck)"
  exit 0
else
  echo "VERDICT: FAIL (see [ERR])"
  exit 2
fi
BASH

chmod +x "$F"
echo "[OK] rebuilt $F"
echo "[NEXT] run: bash /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_commercial_final_selfcheck_v1.sh"
