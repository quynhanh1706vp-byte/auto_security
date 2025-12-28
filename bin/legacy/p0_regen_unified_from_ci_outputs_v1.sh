#!/usr/bin/env bash
set -euo pipefail

CI="/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_20251219_092640"
UI="/home/test/Data/SECURITY_BUNDLE/out/VSP_CI_20251219_092640"
BUNDLE="/home/test/Data/SECURITY_BUNDLE"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_ALIAS="VSP_CI_RUN_20251219_092640"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need rsync; need mkdir; need jq; need curl; need ls

[ -d "$CI" ] || { echo "[ERR] missing CI dir: $CI"; exit 2; }
[ -d "$UI" ] || { echo "[ERR] missing UI dir: $UI"; exit 2; }

echo "[INFO] sync tool outputs CI -> UI run (non-destructive)"
rsync -a \
  --include 'codeql/***' \
  --include 'semgrep/***' \
  --include 'grype/***' \
  --include 'syft/***' \
  --include 'kics/***' \
  --include 'trivy/***' \
  --include 'bandit/***' \
  --include 'gitleaks/***' \
  --include 'degraded/***' \
  --exclude '*' \
  "$CI/" "$UI/"

mkdir -p "$UI/reports"

# Try to run SECURITY_BUNDLE unify if present (best-effort)
if [ -x "$BUNDLE/bin/unify.sh" ]; then
  echo "[INFO] running unify.sh on UI run (if script supports it)"
  ( cd "$BUNDLE" && bin/unify.sh "$UI" ) || echo "[WARN] unify.sh returned non-zero (continue)"
else
  echo "[WARN] $BUNDLE/bin/unify.sh not found/executable; skip regen"
fi

# Verify export size after regen
echo "[INFO] verify export_csv size"
curl -sS -I "$BASE/api/vsp/export_csv?rid=${RID_ALIAS}" | egrep -i 'HTTP/|Content-Length|Content-Disposition' || true
