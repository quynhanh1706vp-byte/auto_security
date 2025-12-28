#!/usr/bin/env bash
set -euo pipefail

OUT_ROOT="/home/test/Data/SECURITY_BUNDLE/out"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need ls; need head; need basename; need mkdir; need cp; need ln; need find; need curl; need jq; need date

SRC="$(ls -1dt "$OUT_ROOT"/VSP_CI_* 2>/dev/null | head -n1 || true)"
[ -n "$SRC" ] || { echo "[ERR] no VSP_CI_* found in $OUT_ROOT"; exit 2; }

RID="$(basename "$SRC")"
ALIAS="VSP_CI_RUN_${RID#VSP_CI_}"          # contains _RUN_ so UI index likely picks it
ALIAS_PATH="$OUT_ROOT/$ALIAS"

echo "[INFO] SRC  : $SRC"
echo "[INFO] RID  : $RID"
echo "[INFO] ALIAS: $ALIAS"

# 1) create/refresh alias symlink
if [ -L "$ALIAS_PATH" ] || [ -e "$ALIAS_PATH" ]; then
  rm -f "$ALIAS_PATH"
fi
ln -s "$RID" "$ALIAS_PATH"
echo "[OK] symlink: $ALIAS_PATH -> $RID"

# 2) ensure reports folder and seed run_gate_summary.json into reports/
mkdir -p "$SRC/reports"

if [ -f "$SRC/reports/run_gate_summary.json" ]; then
  echo "[OK] already has reports/run_gate_summary.json"
else
  if [ -f "$SRC/run_gate_summary.json" ]; then
    cp -f "$SRC/run_gate_summary.json" "$SRC/reports/run_gate_summary.json"
    echo "[OK] copied run_gate_summary.json -> reports/run_gate_summary.json"
  elif [ -f "$SRC/reports/run_gate_summary.json" ]; then
    echo "[OK] reports/run_gate_summary.json exists"
  else
    echo "[WARN] cannot find run_gate_summary.json in $SRC (TGZ may still 404)"
  fi
fi

# (optional) try to seed findings_unified.csv into reports if it exists somewhere
if [ ! -f "$SRC/reports/findings_unified.csv" ]; then
  CAND="$(find "$SRC" -maxdepth 3 -type f -name 'findings_unified.csv' 2>/dev/null | head -n1 || true)"
  if [ -n "$CAND" ]; then
    cp -f "$CAND" "$SRC/reports/findings_unified.csv"
    echo "[OK] copied $(basename "$CAND") -> reports/findings_unified.csv"
  else
    echo "[WARN] no findings_unified.csv found to seed into reports/"
  fi
fi

# 3) verify UI sees alias in runs list
echo "[INFO] verify /api/vsp/runs (expect ALIAS in items)..."
RJSON="$(curl -sS "$BASE/api/vsp/runs?limit=50")"
echo "$RJSON" | jq -r '.ok, .rid_latest, .cache_ttl, (.roots_used|tostring), (.scan_cap|tostring), (.scan_cap_hit|tostring)' || true

echo "$RJSON" | jq -e --arg rid "$ALIAS" '.items[]? | select(.run_id==$rid)' >/dev/null \
  && echo "[OK] alias is visible in items: $ALIAS" \
  || echo "[WARN] alias not visible yet (cache_ttl may delay; try again in few seconds)"

# 4) export smoke by alias
echo "[INFO] export smoke (CSV/TGZ/SHA) for ALIAS=$ALIAS"
curl -sS -I "$BASE/api/vsp/export_csv?rid=${ALIAS}" | sed -n '1,18p' || true
curl -sS -I "$BASE/api/vsp/export_tgz?rid=${ALIAS}&scope=reports" | sed -n '1,18p' || true
curl -sS "$BASE/api/vsp/sha256?rid=${ALIAS}&name=reports/run_gate_summary.json" | jq . || true

echo "[OK] done."
