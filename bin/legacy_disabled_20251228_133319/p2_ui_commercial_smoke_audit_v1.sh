#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need head; need sort; need wc; need date; need mktemp

tmp="$(mktemp -d /tmp/vsp_p2_smoke_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

OK=0; AMBER=0; ERR=0
ok(){ echo "[OK] $*"; OK=$((OK+1)); }
amber(){ echo "[AMBER] $*"; AMBER=$((AMBER+1)); }
err(){ echo "[ERR] $*"; ERR=$((ERR+1)); }

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)

echo "== [0] Basic endpoints reachable =="
for t in "${tabs[@]}"; do
  code="$(curl -s -o /dev/null -w "%{http_code}" "$BASE$t")"
  if [ "$code" = "200" ]; then ok "tab $t => 200"; else err "tab $t => $code"; fi
done

echo
echo "== [1] Extract JS per tab + duplicate JS count =="
all_js="$tmp/all_js.txt"; : > "$all_js"
for t in "${tabs[@]}"; do
  safe="$(echo "$t" | sed 's#[/ ]#_#g')"
  html="$tmp/${safe}.html"
  curl -fsS "$BASE$t" -o "$html" || { err "fetch html $t failed"; continue; }

  jslist="$tmp/${safe}.jslist"
  grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$html" | sort -u > "$jslist" || true
  cat "$jslist" >> "$all_js" || true

  n="$(wc -l < "$jslist" | tr -d ' ')"
  if [ "$n" -gt 0 ]; then ok "$t js_count=$n"; else amber "$t has no js refs (unexpected)"; fi
done
sort -u "$all_js" -o "$all_js"
total_js="$(wc -l < "$all_js" | tr -d ' ')"
ok "unique js urls: $total_js"

# duplicate name check (same basename appears multiple times)
awk -F/ '{print $NF}' "$all_js" | sed 's/\?.*$//' | sort | uniq -c | sort -nr > "$tmp/js_dups.txt"
topdup="$(head -n 1 "$tmp/js_dups.txt" | awk '{print $1}')"
if [ "${topdup:-1}" -ge 5 ]; then amber "some js basenames appear many times (ok if shared bundles). topdup=$(head -n 3 "$tmp/js_dups.txt" | tr '\n' ';')"; else ok "no suspicious js basename duplication"; fi

echo
echo "== [2] HTML sanity checks (missing anchors / placeholders) =="
# Dashboard anchor historically missing
if curl -fsS "$BASE/vsp5" | grep -q 'id="vsp-dashboard-main"'; then
  ok "/vsp5 has #vsp-dashboard-main"
else
  amber "/vsp5 missing #vsp-dashboard-main (check template/anchor inject)"
fi

# Placeholder checks (lightweight)
for t in "${tabs[@]}"; do
  safe="$(echo "$t" | sed 's#[/ ]#_#g')"
  html="$tmp/${safe}.html"
  if grep -qE 'N/A|TODO|PLACEHOLDER' "$html"; then
    amber "$t contains placeholder marker (N/A/TODO/PLACEHOLDER)"
  else
    ok "$t no obvious placeholders"
  fi
done

echo
echo "== [3] API contract checks (RID + run_gate_summary + findings contract) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin)["rid"])' 2>/dev/null || true)"
if [ -n "${RID:-}" ]; then ok "rid_latest=$RID"; else err "rid_latest empty"; fi

# run_gate_summary must be ok
if curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" -o /dev/null; then
  ok "run_gate_summary.json reachable"
else
  err "run_gate_summary.json not reachable via run_file_allow"
fi

# findings contract (reports/findings_unified.json must have findings list)
python3 - "$BASE" "$RID" <<'PY' || exit 3
import sys, json, subprocess
BASE=sys.argv[1]; RID=sys.argv[2]
url=f"{BASE}/api/vsp/run_file_allow?rid={RID}&path=reports/findings_unified.json&limit=10"
raw=subprocess.check_output(["curl","-fsS",url], text=True)
j=json.loads(raw)
f=j.get("findings") or []
it=j.get("items") or []
print("[CHECK] ok=", j.get("ok"), "findings_len=", len(f) if isinstance(f,list) else "NA", "items_len=", len(it) if isinstance(it,list) else "NA")
if not j.get("ok"):
  raise SystemExit(4)
if not isinstance(f, list):
  raise SystemExit(5)
# For commercial: findings should exist; items optional
if len(f) <= 0:
  raise SystemExit(6)
PY
rc=$?
if [ "$rc" -eq 0 ]; then ok "findings contract OK (findings non-empty)"; else err "findings contract FAILED rc=$rc"; fi

echo
echo "== [4] Headers cleanliness (no promote debug headers) =="
hdr="$(curl -sS -D- -o /dev/null "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" || true)"
if echo "$hdr" | grep -qiE 'X-VSP-RFA-PROMOTE|X-VSP-RFA-PROMOTE-DBG|X-VSP-RFA-PROMOTE-ERR'; then
  amber "found X-VSP-RFA* headers (should be hidden for commercial)"
else
  ok "no X-VSP-RFA* headers"
fi

echo
echo "== [5] DS lazy cache policy (no-store expected) =="
ds_hdr="$(curl -sS -D- -o /dev/null "$BASE/static/js/vsp_data_source_lazy_v1.js" || true)"
if echo "$ds_hdr" | grep -qi 'Cache-Control: no-store'; then
  ok "DS lazy Cache-Control: no-store"
else
  amber "DS lazy missing Cache-Control: no-store"
fi

echo
echo "== [RESULT] =="
echo "OK=$OK AMBER=$AMBER ERR=$ERR"
echo "tmp=$tmp"

if [ "$ERR" -gt 0 ]; then
  exit 2
fi
# Allow AMBER but return success (commercial policy: AMBER is warn)
exit 0
