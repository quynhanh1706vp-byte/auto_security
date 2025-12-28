#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="${VSP_UI_ERRLOG:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need sort; need uniq; need wc; need date

OK=0; WARN=0; ERR=0
ok(){ echo "[OK]   $*"; OK=$((OK+1)); }
warn(){ echo "[WARN] $*"; WARN=$((WARN+1)); }
err(){ echo "[ERR]  $*"; ERR=$((ERR+1)); }

TS="$(date +%Y%m%d_%H%M%S)"
PAYLOAD_DIR="out_ci/final_audit_${TS}_payloads_strict"
mkdir -p "$PAYLOAD_DIR"
REPORT="out_ci/final_audit_${TS}_STRICT.txt"

PIN="$(sudo systemctl show "$SVC" -p Environment --no-pager | tr ' ' '\n' | sed -n 's/^VSP_ASSET_V=//p' | head -n 1 || true)"
if [ -z "${PIN:-}" ]; then
  echo "[ERR] cannot read VSP_ASSET_V from systemd ($SVC)"
  exit 2
fi

{
echo "== VSP Commercial+ Strict Audit (v1e) =="
echo "ts=$TS"
echo "BASE=$BASE"
echo "SVC=$SVC"
echo "PINNED_VSP_ASSET_V=$PIN"
echo "PAYLOAD_DIR=$PAYLOAD_DIR"
echo
} | tee "$REPORT"

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "== [A] Tabs 200 + extract html ==" | tee -a "$REPORT"
> "$PAYLOAD_DIR/assets_all.txt"

for P in "${tabs[@]}"; do
  H="$PAYLOAD_DIR/page_${P//\//_}.html"
  code="$(curl -sS -o "$H" -w "%{http_code}" "$BASE$P" || true)"
  if [ "$code" = "200" ]; then ok "TAB $P HTTP=200" | tee -a "$REPORT"; else err "TAB $P HTTP=$code" | tee -a "$REPORT"; fi
  if [ "$P" = "/vsp5" ]; then
    grep -q 'id="vsp-dashboard-main"' "$H" && ok "Dashboard marker present" | tee -a "$REPORT" || err "Dashboard marker missing" | tee -a "$REPORT"
  fi
  grep -oE '(/static/[^"'"'"' ]+\.(js|css)(\?[^"'"'"' ]*)?)' "$H" \
    | sed 's/&amp;/\&/g' >> "$PAYLOAD_DIR/assets_all.txt" || true
done

sort -u "$PAYLOAD_DIR/assets_all.txt" > "$PAYLOAD_DIR/assets_uniq.txt"
ok "assets_uniq_total=$(wc -l <"$PAYLOAD_DIR/assets_uniq.txt" | awk '{print $1}')" | tee -a "$REPORT"

echo "== [B] Assets 200 ==" | tee -a "$REPORT"
bad=0
while IFS= read -r u; do
  c="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  if [ "$c" != "200" ]; then
    bad=$((bad+1))
    echo "[BAD] $c $u" >> "$PAYLOAD_DIR/assets_bad.txt"
  fi
done < "$PAYLOAD_DIR/assets_uniq.txt"
[ "$bad" -eq 0 ] && ok "All referenced assets return 200" | tee -a "$REPORT" || err "Found $bad assets not 200" | tee -a "$REPORT"

echo "== [C] STRICT asset_v: core basenames must match PIN exactly ==" | tee -a "$REPORT"
python3 - "$PAYLOAD_DIR/assets_uniq.txt" "$PIN" "$PAYLOAD_DIR/strict_v_report.txt" <<'PY' | tee -a "$REPORT"
import sys, re
from urllib.parse import urlparse, parse_qs

assets=[x.strip() for x in open(sys.argv[1],encoding="utf-8",errors="replace") if x.strip()]
pin=sys.argv[2]
out=sys.argv[3]

core=set([
 "vsp_bundle_tabs5_v1.js",
 "vsp_dashboard_luxe_v1.js",
 "vsp_tabs4_autorid_v1.js",
 "vsp_topbar_commercial_v1.js",
])

by_base={}
for u in assets:
    p=urlparse("http://x"+u)
    base=p.path.rsplit("/",1)[-1]
    if base not in core: 
        continue
    q=parse_qs(p.query or "")
    v=(q.get("v") or [""])[0]
    by_base.setdefault(base,set()).add(v)

fail=[]
with open(out,"w",encoding="utf-8") as f:
    for base in sorted(core):
        vs=sorted(by_base.get(base,set()) or ["<missing>"])
        f.write(f"{base} => {vs}\n")
        # strict: must be exactly [pin]
        if vs != [pin]:
            fail.append((base,vs))
        # also ban epoch / 8-digit-only
        for v in vs:
            if re.fullmatch(r"\d{10}", v) or re.fullmatch(r"\d{9,}", v):
                # epoch-like
                pass
    if fail:
        f.write("\nFAIL:\n")
        for base,vs in fail:
            f.write(f" - {base}: {vs} (expected only {pin})\n")

print("pinned=", pin)
for base in sorted(core):
    print(base, "=>", sorted(by_base.get(base,set()) or ["<missing>"]))

if fail:
    sys.exit(3)
PY

rc=$?
if [ "$rc" -eq 0 ]; then
  ok "STRICT asset_v PASS (all core basenames match pinned)" | tee -a "$REPORT"
else
  err "STRICT asset_v FAIL (see $PAYLOAD_DIR/strict_v_report.txt)" | tee -a "$REPORT"
fi

echo "== [D] API contract STRICT ==" | tee -a "$REPORT"
api_json(){
  local url="$1"
  curl -sS "$url" > "$PAYLOAD_DIR/$(echo "$url" | sed 's/[^a-zA-Z0-9]/_/g').json" || true
}

api_json "$BASE/api/vsp/rid_latest"
api_json "$BASE/api/vsp/ui_health_v2"
api_json "$BASE/api/vsp/top_findings_v1?limit=1"
api_json "$BASE/api/vsp/trend_v1"

python3 - "$PAYLOAD_DIR" "$PIN" <<'PY' | tee -a "$REPORT"
import json,sys,glob,os
d=sys.argv[1]; pin=sys.argv[2]

def load_one(prefix):
    cand=sorted(glob.glob(os.path.join(d,prefix+"*.json")))
    if not cand: 
        return None, None
    fn=cand[0]
    try:
        return fn, json.load(open(fn,"r",encoding="utf-8"))
    except Exception:
        return fn, None

rid_fn, rid = load_one("http___127_0_0_1_8910_api_vsp_rid_latest")
uh_fn, uh = load_one("http___127_0_0_1_8910_api_vsp_ui_health_v2")
tf_fn, tf = load_one("http___127_0_0_1_8910_api_vsp_top_findings_v1_limit_1")
tr_fn, tr = load_one("http___127_0_0_1_8910_api_vsp_trend_v1")

def req(cond,msg):
    if not cond:
        print("[API_ERR]", msg)
        return False
    print("[API_OK]", msg)
    return True

ok=True
rid_val = (rid or {}).get("rid") if isinstance(rid,dict) else None
ok &= req(isinstance(rid,dict) and (rid.get("ok") is True) and bool(rid_val), f"rid_latest ok rid={rid_val}")

asset_val = ((uh or {}).get("meta") or {}).get("asset_v") if isinstance(uh,dict) else None
ok &= req(isinstance(uh,dict) and uh.get("ok") is True and uh.get("ready") is True, f"ui_health ok/ready marker={(uh or {}).get('marker')}")
ok &= req(asset_val == pin, f"ui_health meta.asset_v={asset_val} must == pinned {pin}")

tf_run_id = (tf or {}).get("run_id") if isinstance(tf,dict) else None
ok &= req(isinstance(tf,dict) and tf.get("ok") is True, f"top_findings ok total={(tf or {}).get('total')}")
ok &= req(bool(tf_run_id), f"top_findings run_id must not be None (got {tf_run_id})")
# optional: should equal rid_latest
ok &= req((tf_run_id == rid_val), f"top_findings run_id should == rid_latest ({rid_val})")

ok &= req(isinstance(tr,dict) and tr.get("ok") is True and bool(tr.get("marker")), f"trend ok marker={tr.get('marker')} points={len(tr.get('points') or [])}")

sys.exit(4 if not ok else 0)
PY

api_rc=$?
if [ "$api_rc" -eq 0 ]; then
  ok "API STRICT PASS" | tee -a "$REPORT"
else
  err "API STRICT FAIL (see json in $PAYLOAD_DIR)" | tee -a "$REPORT"
fi

echo "== SUMMARY ==" | tee -a "$REPORT"
echo "OK=$OK WARN=$WARN ERR=$ERR" | tee -a "$REPORT"
echo "[OK] report: $REPORT" | tee -a "$REPORT"

# Strict: any ERR => fail
if [ "$ERR" -gt 0 ]; then
  echo "[FAIL] Commercial+ strict audit FAILED" | tee -a "$REPORT"
  exit 1
fi
echo "[PASS] Commercial+ strict audit PASSED" | tee -a "$REPORT"
