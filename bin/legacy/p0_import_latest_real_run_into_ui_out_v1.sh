#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
DST_ROOT="/home/test/Data/SECURITY_BUNDLE/out"
SRC_ROOT="/home/test/Data/SECURITY-10-10-v4/out_ci"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need ls; need rsync; need mkdir; need date; need curl; need jq

mkdir -p "$DST_ROOT"

SRC="$(ls -1dt "$SRC_ROOT"/VSP_CI_* 2>/dev/null | head -n1 || true)"
[ -n "$SRC" ] || { echo "[ERR] no source run found in $SRC_ROOT (pattern VSP_CI_*)"; exit 2; }

RID="$(basename "$SRC")"
DST="$DST_ROOT/$RID"

echo "[INFO] import run:"
echo "  SRC=$SRC"
echo "  DST=$DST"

# copy run dir (idempotent)
rsync -a --delete \
  --exclude '*.tmp' \
  "$SRC/" "$DST/"

echo "[OK] imported: $RID"

# verify UI sees it as rid_latest (or at least present in items)
echo "[INFO] verify /api/vsp/runs contract..."
RJSON="$(curl -sS "$BASE/api/vsp/runs?limit=20")"
echo "$RJSON" | jq -r '.ok, .rid_latest, .cache_ttl, (.roots_used|tostring), (.scan_cap|tostring), (.scan_cap_hit|tostring)' || true

echo "[INFO] check rid present in items..."
echo "$RJSON" | jq -e --arg rid "$RID" '.items[]? | select(.run_id==$rid)' >/dev/null \
  && echo "[OK] rid present in items: $RID" \
  || echo "[WARN] rid not found in items (maybe filtered by scan_cap/roots?)"

# export smoke for this RID
echo "[INFO] export smoke (CSV/TGZ/SHA) for RID=$RID"
curl -sS -I "$BASE/api/vsp/export_csv?rid=${RID}" | sed -n '1,18p'
curl -sS -I "$BASE/api/vsp/export_tgz?rid=${RID}&scope=reports" | sed -n '1,18p'
curl -sS "$BASE/api/vsp/sha256?rid=${RID}&name=reports/run_gate_summary.json" | jq . || true

echo "[OK] done."
