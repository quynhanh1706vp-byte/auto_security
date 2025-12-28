#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need awk; need grep; need head; need wc; need python3; need date

G=0; A=0; R=0
green(){ echo "[GREEN] $*"; G=$((G+1)); }
amber(){ echo "[AMBER] $*"; A=$((A+1)); }
red(){ echo "[RED] $*"; R=$((R+1)); }

warm(){
  for i in $(seq 1 80); do
    if curl -fsS --connect-timeout 2 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      green "UI up (selfcheck): $BASE"
      return 0
    fi
    sleep 0.2
  done
  red "UI not reachable (selfcheck_p0 fail)"
  return 1
}

fetch_hdr(){
  local url="$1" hdr="$2" body="$3"
  rm -f "$hdr" "$body" || true
  curl -sS --connect-timeout 2 --max-time 12 -D "$hdr" -o "$body" "$url" || true
  [ -f "$hdr" ] || : > "$hdr"
  [ -f "$body" ] || : > "$body"
}

ct_of(){ awk 'BEGIN{IGNORECASE=1} /^Content-Type:/{print $0; exit}' "$1" | tr -d '\r' || true; }
status_of(){ awk 'BEGIN{IGNORECASE=1} /^HTTP\//{print $2; exit}' "$1" | tr -d '\r' || true; }

pick_rid(){
  local url="$BASE/api/vsp/runs?limit=5&offset=0"
  for i in $(seq 1 80); do
    fetch_hdr "$url" /tmp/_a3_runs.hdr /tmp/_a3_runs.bin
    local ct; ct="$(ct_of /tmp/_a3_runs.hdr)"
    local bytes; bytes="$(wc -c </tmp/_a3_runs.bin 2>/dev/null || echo 0)"
    if echo "$ct" | grep -qi 'application/json' && [ "${bytes:-0}" -gt 20 ]; then
      RID="$(python3 - <<'PY' 2>/dev/null || true
import json
j=json.load(open("/tmp/_a3_runs.bin","r",encoding="utf-8", errors="replace"))
runs=j.get("runs") or []
r0=runs[0] if runs and isinstance(runs[0], dict) else {}
print((r0.get("rid") or r0.get("id") or r0.get("run_id") or "").strip())
PY
)"
      if [ -n "${RID:-}" ]; then
        green "Picked RID=$RID"
        echo "$RID"
        return 0
      fi
    fi
    sleep 0.2
  done
  red "Pick RID failed (runs not stable JSON)"
  echo ""
  return 1
}

echo "== [P38] commercial_ui_audit_v3 =="
echo "BASE=$BASE"

warm || true

echo "== [1] Tabs (HTML + CSP_RO) =="
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for t in "${tabs[@]}"; do
  fetch_hdr "$BASE$t" /tmp/_a3_tab.hdr /tmp/_a3_tab.bin
  st="$(status_of /tmp/_a3_tab.hdr)"
  ct="$(ct_of /tmp/_a3_tab.hdr)"
  if [ "$st" = "200" ]; then green "TAB $t => 200"; else red "TAB $t => $st"; fi
  if echo "$ct" | grep -qi 'text/html'; then green "TAB $t => Content-Type html"; else amber "TAB $t => Content-Type not html ($ct)"; fi
  csp="$(awk 'BEGIN{IGNORECASE=1} /^Content-Security-Policy-Report-Only:/{c++} END{print c+0}' /tmp/_a3_tab.hdr)"
  if [ "$csp" -eq 1 ]; then green "TAB $t CSP_RO single"; else amber "TAB $t CSP_RO count=$csp (expect 1)"; fi
done

echo "== [2] Pick RID =="
RID="$(pick_rid || true)"
[ -n "$RID" ] || RID="VSP_CI_20251211_133204"
echo "RID=$RID"

echo "== [3] Core APIs =="
apis=(
  "/api/vsp/selfcheck_p0"
  "/api/vsp/runs?limit=10&offset=0"
  "/api/vsp/runs_index_v3"
  "/api/vsp/datasource_v2"
  "/api/vsp/findings?limit=5&offset=0"
  "/api/vsp/settings_v1"
  "/api/vsp/settings_ui_v1"
  "/api/vsp/rule_overrides_v1"
  "/api/vsp/rule_overrides_ui_v1"
  "/api/vsp/dashboard_v3"
  "/api/vsp/dashboard_commercial_v2"
  "/api/vsp/dashboard_extras_v1"
)
for a in "${apis[@]}"; do
  fetch_hdr "$BASE$a" /tmp/_a3_api.hdr /tmp/_a3_api.bin
  st="$(status_of /tmp/_a3_api.hdr)"
  ct="$(ct_of /tmp/_a3_api.hdr)"
  if [ "$st" = "200" ]; then green "API OK: $a"; else red "API FAIL($st): $a"; fi
  if echo "$ct" | grep -qi 'application/json'; then :; else amber "API CT not json: $a ($ct)"; fi
done

echo "== [4] P35 Rule Overrides CRUD =="
RID2="ro_test_$(date +%s)"
payload="$(python3 - <<PY
import json
print(json.dumps({
 "id": "$RID2",
 "tool": "semgrep",
 "rule_id": "TEST.P35.DEMO",
 "action": "suppress",
 "severity_override": "INFO",
 "reason": "p35 smoke",
 "enabled": True
}))
PY
)"
fetch_hdr "$BASE/api/vsp/rule_overrides_v1/" /tmp/_a3_ro0.hdr /tmp/_a3_ro0.bin
if grep -q '"ok":' /tmp/_a3_ro0.bin; then green "RO GET ok"; else red "RO GET not json"; fi

fetch_hdr "$BASE/api/vsp/rule_overrides_v1/" /tmp/_a3_post.hdr /tmp/_a3_post.bin
curl -sS --connect-timeout 2 --max-time 12 -D /tmp/_a3_post.hdr \
  -H "Content-Type: application/json" -X POST \
  --data "$payload" "$BASE/api/vsp/rule_overrides_v1/" -o /tmp/_a3_post.bin || true
if grep -q "\"id\":\"$RID2\"" /tmp/_a3_post.bin; then green "RO POST created"; else red "RO POST failed"; fi

fetch_hdr "$BASE/api/vsp/rule_overrides_v1/" /tmp/_a3_ro1.hdr /tmp/_a3_ro1.bin
python3 - <<PY >/tmp/_a3_ro1_chk.txt 2>/dev/null || true
import json
j=json.load(open("/tmp/_a3_ro1.bin","r",encoding="utf-8", errors="replace"))
items=j.get("items") or []
print(any(isinstance(x,dict) and x.get("id")== "$RID2" for x in items))
PY
if grep -q 'True' /tmp/_a3_ro1_chk.txt; then green "RO GET contains created"; else red "RO GET missing created"; fi

curl -sS --connect-timeout 2 --max-time 12 -D /tmp/_a3_del.hdr \
  -H "Content-Type: application/json" -X DELETE \
  --data "$(printf '{"id":"%s"}' "$RID2")" \
  "$BASE/api/vsp/rule_overrides_v1/" -o /tmp/_a3_del.bin || true
if grep -q "\"deleted\":\"$RID2\"" /tmp/_a3_del.bin; then green "RO DELETE ok"; else red "RO DELETE failed"; fi

fetch_hdr "$BASE/api/vsp/rule_overrides_v1/" /tmp/_a3_ro2.hdr /tmp/_a3_ro2.bin
python3 - <<PY >/tmp/_a3_ro2_chk.txt 2>/dev/null || true
import json
j=json.load(open("/tmp/_a3_ro2.bin","r",encoding="utf-8", errors="replace"))
items=j.get("items") or []
print(not any(isinstance(x,dict) and x.get("id")== "$RID2" for x in items))
PY
if grep -q 'True' /tmp/_a3_ro2_chk.txt; then green "RO removed persisted"; else red "RO still exists"; fi

echo "== [5] P36 Paging + RID correctness =="
fetch_hdr "$BASE/api/vsp/findings?limit=5&offset=0" /tmp/_a3_f0.hdr /tmp/_a3_f0.bin
b0="$(wc -c </tmp/_a3_f0.bin 2>/dev/null || echo 0)"
if [ "$b0" -lt 200000 ]; then green "findings paging small (bytes=$b0)"; else amber "findings too big (bytes=$b0)"; fi

fetch_hdr "$BASE/api/vsp/findings?limit=5&offset=5" /tmp/_a3_f5.hdr /tmp/_a3_f5.bin
python3 - <<'PY' >/tmp/_a3_fcmp.txt 2>/dev/null || true
import json
a=json.load(open("/tmp/_a3_f0.bin","r",encoding="utf-8", errors="replace"))
b=json.load(open("/tmp/_a3_f5.bin","r",encoding="utf-8", errors="replace"))
ia=a.get("items") or []
ib=b.get("items") or []
print((len(ia),len(ib), (ia[0] if ia else None)==(ib[0] if ib else None)))
PY
if grep -q '(5, 5, False)' /tmp/_a3_fcmp.txt; then green "paging offset differs"; else amber "paging offset suspicious: $(cat /tmp/_a3_fcmp.txt 2>/dev/null || true)"; fi

fetch_hdr "$BASE/api/vsp/datasource_v2?rid=RID_DOES_NOT_EXIST_123" /tmp/_a3_dsbad.hdr /tmp/_a3_dsbad.bin
if grep -q '"ok":false' /tmp/_a3_dsbad.bin; then green "datasource rid missing => ok:false"; else amber "datasource rid missing not ok:false"; fi

echo "== [6] P37 Export contract =="
for fmt in html pdf zip; do
  fetch_hdr "$BASE/api/vsp/export?rid=$RID&fmt=$fmt" /tmp/_a3_e.hdr /tmp/_a3_e.bin
  st="$(status_of /tmp/_a3_e.hdr)"
  ct="$(ct_of /tmp/_a3_e.hdr)"
  sz="$(wc -c </tmp/_a3_e.bin 2>/dev/null || echo 0)"
  if [ "$st" = "200" ] && [ "$sz" -gt 0 ]; then
    case "$fmt" in
      html) echo "$ct" | grep -qi 'text/html' && green "export html OK (bytes=$sz)" || amber "export html CT=$ct";;
      pdf)  echo "$ct" | grep -qi 'application/pdf' && green "export pdf OK (bytes=$sz)" || amber "export pdf CT=$ct";;
      zip)  echo "$ct" | grep -qi 'application/zip' && green "export zip OK (bytes=$sz)" || amber "export zip CT=$ct";;
    esac
  else
    red "export $fmt FAIL st=$st bytes=$sz"
  fi
done

echo "== [SUMMARY] =="
echo "GREEN=$G AMBER=$A RED=$R"
if [ "$R" -eq 0 ]; then
  echo "[VERDICT] PASS (no RED)"
else
  echo "[VERDICT] FAIL (has RED)"
  exit 1
fi
