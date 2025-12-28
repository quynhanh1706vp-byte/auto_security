#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need ss; need awk; need sed; command -v jq >/dev/null 2>&1 && HAS_JQ=1 || HAS_JQ=0

ok(){ echo "[OK] $*"; }
bad(){ echo "[FAIL] $*"; exit 1; }

echo "== LISTEN =="
ss -ltnp | grep ':8910' >/dev/null && ok "8910 listening" || bad "8910 not listening"

hit_head(){
  local path="$1"; local want="$2"
  local code
  code="$(curl -sS -o /dev/null -w "%{http_code}" -I "${BASE}${path}" || true)"
  if [ "$code" = "$want" ]; then ok "HEAD ${path} -> ${code}"; else echo "[WARN] HEAD ${path} -> ${code} (want ${want})"; fi
}

hit_get200(){
  local path="$1"
  local code
  code="$(curl -sS -o /dev/null -w "%{http_code}" "${BASE}${path}" || true)"
  [ "$code" = "200" ] && ok "GET ${path} -> 200" || bad "GET ${path} -> ${code}"
}

echo "== PAGES =="
hit_head "/" "200" || true
hit_head "/" "302" || true
hit_get200 "/vsp5"
hit_get200 "/runs"
hit_get200 "/data_source"
hit_get200 "/settings"
hit_get200 "/rule_overrides"

echo "== API runs =="
hit_get200 "/api/vsp/runs?limit=1"

if [ "$HAS_JQ" = "1" ]; then
  RID="$(curl -sS "${BASE}/api/vsp/runs?limit=1" | jq -r '.items[0].run_id // empty' 2>/dev/null || true)"
  if [ -n "${RID:-}" ]; then
    echo "== EXPORT (rid=${RID}) =="
    curl -sS -I "${BASE}/api/vsp/export_csv?rid=${RID}" | sed -n '1,12p'
    curl -sS -I "${BASE}/api/vsp/export_tgz?rid=${RID}&scope=reports" | sed -n '1,12p'
    curl -sS "${BASE}/api/vsp/sha256?rid=${RID}&name=reports/run_gate_summary.json" | head -c 200; echo
    ok "export endpoints reachable"
  else
    echo "[WARN] cannot parse RID (jq ok but response unexpected)"
  fi
else
  echo "[WARN] jq not found -> skip RID/export checks"
fi

echo "== DONE =="
