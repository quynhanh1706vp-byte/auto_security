#!/usr/bin/env bash
set -euo pipefail

BASE="/home/test/Data/SECURITY_BUNDLE"
PY="$BASE/bin/vsp_unify_findings_always8_v1.py"

# find unify script
U=""
for c in "$BASE/bin/fallback_unify.sh" "$BASE/bin/unify.sh" "$BASE/bin/unify_v1.sh"; do
  [ -f "$c" ] && U="$c" && break
done
if [ -z "$U" ]; then
  U="$(ls -1 "$BASE/bin"/*unify*.sh 2>/dev/null | head -n 1 || true)"
fi

[ -n "$U" ] || { echo "[ERR] cannot locate unify script in $BASE/bin"; exit 2; }
[ -f "$PY" ] || { echo "[ERR] missing $PY"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$U" "$U.bak_call_unifier_${TS}"
echo "[BACKUP] $U.bak_call_unifier_${TS}"

TAG="# === VSP_CALL_UNIFY_FINDINGS_ALWAYS8_V1 ==="
if grep -q "$TAG" "$U"; then
  echo "[OK] already patched $U"
  exit 0
fi

cat >> "$U" <<EOF

$TAG
# Build unified findings for Data Source (commercial): write findings_unified.json + reports/findings_unified.json
if [ -n "\${RUN_DIR:-}" ] && [ -d "\$RUN_DIR" ]; then
  python3 -u "$PY" "\$RUN_DIR" || true
fi
EOF

echo "[OK] patched $U (append call to unifier)"
