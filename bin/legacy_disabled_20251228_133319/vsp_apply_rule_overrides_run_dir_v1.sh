#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="${1:-}"
[ -n "$RUN_DIR" ] || { echo "Usage: $0 <RUN_DIR> [OVERRIDES_JSON]"; exit 2; }

OV="${2:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_rule_overrides_v1.json}"
F_RAW="$RUN_DIR/findings_unified.json"
F_OUT="$RUN_DIR/findings_effective.json"

[ -f "$F_RAW" ] || { echo "[ERR] missing $F_RAW"; exit 3; }
[ -f "$OV" ] || { echo "[ERR] missing overrides: $OV"; exit 4; }

python3 - <<PY
import json, sys
from vsp_rule_overrides_apply_v1 import apply_file
out = apply_file("$F_RAW", "$OV", "$F_OUT")
print("[OK] wrote", "$F_OUT")
print(json.dumps({"delta": out.get("delta"), "effective_total": out.get("effective_summary",{}).get("total")}, ensure_ascii=False, indent=2))
PY
