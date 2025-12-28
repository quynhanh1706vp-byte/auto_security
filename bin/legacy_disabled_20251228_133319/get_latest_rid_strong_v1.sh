#!/usr/bin/env bash
set -euo pipefail

# 1) try API runs_index
RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=5&hide_empty=0&filter=0' \
  | jq -er '..|.run_id?|select(type=="string")' 2>/dev/null | head -n1 || true)"

if [ -n "${RID:-}" ] && [ "${RID:-}" != "null" ]; then
  echo "$RID"
  exit 0
fi

# 2) fallback: newest RUN_DIR on FS
LAST="$(ls -1dt /home/test/Data/SECURITY-*/out_ci/VSP_CI_* 2>/dev/null | head -n1 || true)"
[ -n "${LAST:-}" ] || { echo "[ERR] cannot find any VSP_CI_* run dir"; exit 2; }

BN="$(basename "$LAST")"
echo "RUN_${BN}"
