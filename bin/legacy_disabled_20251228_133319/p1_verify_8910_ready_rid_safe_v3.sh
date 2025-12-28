#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need head; need sed

get_json_or_empty() {
  local url="$1"
  local h b
  h="$(mktemp)"; b="$(mktemp)"
  curl -sS -D "$h" --max-time 5 "$url" -o "$b" || true
  local code ctype
  code="$(awk 'NR==1{print $2}' "$h" 2>/dev/null || true)"
  ctype="$(awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}' "$h" | tail -n1 | tr -d '\r' || true)"
  if [ "${code:-}" != "200" ]; then
    echo "[WARN] $url -> HTTP ${code:-?}" >&2
    sed -n '1,12p' "$h" >&2
    rm -f "$h" "$b"
    echo ""
    return 0
  fi
  if echo "${ctype:-}" | grep -q "application/json"; then
    cat "$b"
  else
    echo "[WARN] $url -> 200 but non-JSON ctype='${ctype:-?}'" >&2
    sed -n '1,12p' "$h" >&2
    echo "[BODY head]" >&2
    head -c 240 "$b" >&2; echo >&2
    echo ""
  fi
  rm -f "$h" "$b"
}

RID=""

echo "== try RID from /api/vsp/runs?limit=1 =="
RUNS_JSON="$(get_json_or_empty "$BASE/api/vsp/runs?limit=1")"
if [ -n "${RUNS_JSON:-}" ]; then
  RID="$(python3 - <<'PY2' 2>/dev/null || true
import json,sys
try:
  o=json.loads(sys.stdin.read())
  items=o.get("items") or []
  print(items[0].get("run_id","") if items else "")
except Exception:
  print("")
PY2
<<<"$RUNS_JSON")"
fi

if [ -z "${RID:-}" ]; then
  echo "[WARN] RID not available from /api/vsp/runs; fallback to dash_kpis rid"
  KPIS_JSON="$(get_json_or_empty "$BASE/api/vsp/dash_kpis")"
  if [ -n "${KPIS_JSON:-}" ]; then
    RID="$(python3 - <<'PY3' 2>/dev/null || true
import json,sys
try:
  o=json.loads(sys.stdin.read())
  print(o.get("rid",""))
except Exception:
  print("")
PY3
<<<"$KPIS_JSON")"
  fi
fi

if [ -z "${RID:-}" ]; then
  echo "[ERR] could not determine RID (runs not JSON, kpis not JSON)"
  exit 3
fi

echo "[OK] RID=$RID"
echo "== verify dash endpoints =="
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 240; echo
curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 240; echo
