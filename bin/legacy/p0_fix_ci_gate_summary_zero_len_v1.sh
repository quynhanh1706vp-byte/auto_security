#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need ls; need wc; need cp; need mkdir

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

RID_GATE_ROOT="$(curl -sS "$BASE/api/vsp/runs?limit=5" | python3 - <<'PY'
import sys, json
d=json.load(sys.stdin)
print((d.get("rid_latest_gate_root") or d.get("rid_latest") or "").strip())
PY
)"
[ -n "$RID_GATE_ROOT" ] || { echo "[ERR] cannot detect rid_latest_gate_root"; exit 2; }
echo "[RID_GATE_ROOT]=$RID_GATE_ROOT"

# expected run dirs
D_UI="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/${RID_GATE_ROOT}"
D_OUT="/home/test/Data/SECURITY_BUNDLE/out/${RID_GATE_ROOT}"

# ensure at least one dir exists
if [ ! -d "$D_UI" ] && [ ! -d "$D_OUT" ]; then
  echo "[ERR] run dir not found: $D_UI or $D_OUT"
  exit 2
fi

TARGET=""
if [ -d "$D_UI" ]; then TARGET="$D_UI/run_gate_summary.json"; fi
if [ -z "$TARGET" ] && [ -d "$D_OUT" ]; then TARGET="$D_OUT/run_gate_summary.json"; fi
[ -n "$TARGET" ] || { echo "[ERR] cannot decide TARGET"; exit 2; }

mkdir -p "$(dirname "$TARGET")"

size_of(){ [ -f "$1" ] && wc -c < "$1" 2>/dev/null || echo 0; }

echo "== current sizes =="
for p in \
  "$D_UI/run_gate_summary.json" "$D_UI/run_gate.json" "$D_UI/reports/run_gate_summary.json" "$D_UI/reports/run_gate.json" \
  "$D_OUT/run_gate_summary.json" "$D_OUT/run_gate.json" "$D_OUT/reports/run_gate_summary.json" "$D_OUT/reports/run_gate.json"
do
  [ -e "$p" ] || continue
  echo " - $(size_of "$p") bytes  $p"
done

# choose best source (must be non-empty + valid JSON)
pick_source_py='
import json, sys, os
cands = sys.argv[1:]
best = ""
for p in cands:
  try:
    if not os.path.isfile(p): 
      continue
    if os.path.getsize(p) < 50:
      continue
    with open(p, "rb") as f:
      b = f.read()
    # must be json
    json.loads(b.decode("utf-8", "replace"))
    best = p
    break
  except Exception:
    continue
print(best)
'

SRC="$(python3 -c "$pick_source_py" \
  "$D_UI/run_gate.json" \
  "$D_UI/reports/run_gate_summary.json" \
  "$D_UI/reports/run_gate.json" \
  "$D_OUT/run_gate.json" \
  "$D_OUT/reports/run_gate_summary.json" \
  "$D_OUT/reports/run_gate.json" \
  "$D_UI/run_gate_summary.json" \
  "$D_OUT/run_gate_summary.json" \
)"

T_SIZE="$(size_of "$TARGET")"
echo "[TARGET]=$TARGET size=${T_SIZE}"

if [ -z "$SRC" ]; then
  echo "[ERR] cannot find any non-empty valid JSON gate source to fill $TARGET"
  echo "[HINT] check if CI run actually produced run_gate.json / run_gate_summary.json"
  exit 2
fi
echo "[SRC]=$SRC"

if [ "$T_SIZE" -ge 50 ]; then
  echo "[OK] target already non-empty (>=50B). Skip overwrite."
else
  if [ -f "$TARGET" ]; then
    cp -f "$TARGET" "${TARGET}.bak_zero_${TS}" || true
    echo "[BACKUP] ${TARGET}.bak_zero_${TS}"
  fi
  cp -f "$SRC" "$TARGET"
  echo "[FIXED] copied"
  echo " - from: $SRC"
  echo " - to  : $TARGET"
fi

echo
echo "== verify GET from backend (must output JSON, non-empty) =="
curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID_GATE_ROOT&path=run_gate_summary.json" | python3 -c 'import sys; b=sys.stdin.buffer.read(); print("bytes=",len(b)); print(b[:180].decode("utf-8","replace"))'
