#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
die(){ echo "[ERR] $*"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || die "missing cmd: $1"; }
need curl; need jq; need grep; need sed; need awk

echo "== HTTP pages =="
for p in / /vsp5 /runs /data_source /settings /rule_overrides; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$p" || true)"
  [[ "$code" =~ ^(200|302)$ ]] && ok "GET $p => $code" || warn "GET $p => $code"
done

echo
echo "== runs api contract =="
curl -sS -D /tmp/hdr.txt "$BASE/api/vsp/runs?limit=1" -o /tmp/runs.json || true
code="$(awk 'NR==1{print $2}' /tmp/hdr.txt 2>/dev/null || true)"
[[ "$code" == "200" ]] || warn "/api/vsp/runs?limit=1 http=$code"
grep -qi '^X-VSP-RUNS-CONTRACT:' /tmp/hdr.txt && ok "X-VSP-RUNS-CONTRACT present" || warn "missing X-VSP-RUNS-CONTRACT"
jq -e '.ok==true and (.items|type)=="array" and (.items|length>=1) and (.rid_latest|type)=="string"' /tmp/runs.json >/dev/null \
  && ok "runs.json ok/items/rid_latest OK" || warn "runs.json contract NOT OK"

RID="$(jq -r '.rid_latest // empty' /tmp/runs.json)"
[[ -n "$RID" ]] || warn "rid_latest empty"

echo
echo "== export endpoints (latest rid) =="
if [[ -n "${RID:-}" ]]; then
  curl -sS -I "$BASE/api/vsp/export_csv?rid=$RID" | sed -n '1,12p' | grep -q '200' && ok "export_csv 200" || warn "export_csv not 200"
  curl -sS -I "$BASE/api/vsp/export_tgz?rid=$RID&scope=reports" | sed -n '1,12p' | grep -q '200' && ok "export_tgz 200" || warn "export_tgz not 200"
  curl -sS "$BASE/api/vsp/sha256?rid=$RID&name=reports/run_gate_summary.json" | jq -e '.ok==true' >/dev/null \
    && ok "sha256 ok" || warn "sha256 not ok"
else
  warn "skip export checks: no RID"
fi

echo
echo "== template cache-bust sanity =="
# phải đúng 1 query ?v=... , không được ?v=... ?v=...
bad=0
for f in templates/*.html; do
  if grep -q 'vsp_p1_page_boot_v1\.js' "$f"; then
    line="$(grep -n 'vsp_p1_page_boot_v1\.js' "$f" | head -n1 | cut -d: -f2-)"
    echo " - $(basename "$f"): $line"
    echo "$line" | grep -q '\?v=.*\?v=' && { warn "double ?v in $(basename "$f")"; bad=$((bad+1)); }
  fi
done
[[ "$bad" -eq 0 ]] && ok "no double ?v" || warn "double ?v found=$bad"

echo
echo "== error log quick scan =="
LOG="out_ci/ui_8910.error.log"
if [[ -s "$LOG" ]]; then
  tail -n 120 "$LOG" | egrep -n "Traceback|SyntaxError|Exception|ERROR" || true
  ok "tailed $LOG (check above if any)"
else
  ok "no error log yet: $LOG"
fi

echo
echo "[NEXT] Nếu Dashboard vẫn báo 503 nhưng curl /api/vsp/runs?limit=1 = 200 => 100% là JS cache/đang fetch nhầm endpoint. Chạy script debug ở bước 2."
