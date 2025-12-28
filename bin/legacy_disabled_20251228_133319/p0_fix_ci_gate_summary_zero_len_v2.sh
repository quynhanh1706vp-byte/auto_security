#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need ls; need wc; need cp; need mkdir; need head

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== sanity: /api/vsp/runs (raw head 1KB) =="
RAW="$(curl -sS --max-time 4 "$BASE/api/vsp/runs?limit=5" || true)"
echo "$RAW" | head -c 300; echo
echo "[RAW_BYTES]=$(printf %s "$RAW" | wc -c | tr -d ' ')"

RID_GATE_ROOT=""

# 1) try parse API if it looks like JSON
if printf %s "$RAW" | grep -q '^{'; then
  RID_GATE_ROOT="$(printf %s "$RAW" | python3 - <<'PY' || true
import sys, json
try:
  d=json.load(sys.stdin)
  rid=(d.get("rid_latest_gate_root") or d.get("rid_latest") or "").strip()
  print(rid)
except Exception:
  pass
PY
)"
fi

# 2) fallback: pick latest VSP_CI_RUN_* directory from filesystem
if [ -z "${RID_GATE_ROOT:-}" ]; then
  echo "[WARN] API rid_latest_gate_root unavailable -> fallback to filesystem"
  C1="$(ls -1dt /home/test/Data/SECURITY_BUNDLE/ui/out_ci/VSP_CI_RUN_* 2>/dev/null | head -n1 || true)"
  C2="$(ls -1dt /home/test/Data/SECURITY_BUNDLE/out/VSP_CI_RUN_* 2>/dev/null | head -n1 || true)"
  PICK="${C1:-${C2:-}}"
  if [ -n "$PICK" ]; then
    RID_GATE_ROOT="$(basename "$PICK")"
  fi
fi

[ -n "${RID_GATE_ROOT:-}" ] || { echo "[ERR] cannot detect gate_root RID (API empty + no VSP_CI_RUN_* folder)"; exit 2; }
echo "[RID_GATE_ROOT]=$RID_GATE_ROOT"

D_UI="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/${RID_GATE_ROOT}"
D_OUT="/home/test/Data/SECURITY_BUNDLE/out/${RID_GATE_ROOT}"

exists_dir=""
if [ -d "$D_UI" ]; then exists_dir="$D_UI"; fi
if [ -z "$exists_dir" ] && [ -d "$D_OUT" ]; then exists_dir="$D_OUT"; fi
[ -n "$exists_dir" ] || { echo "[ERR] run dir not found: $D_UI or $D_OUT"; exit 2; }

TARGET="$exists_dir/run_gate_summary.json"
mkdir -p "$(dirname "$TARGET")"

size_of(){ [ -f "$1" ] && wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0; }

echo "== sizes in chosen run dir ($(basename "$exists_dir")) =="
for p in \
  "$exists_dir/run_gate_summary.json" \
  "$exists_dir/run_gate.json" \
  "$exists_dir/reports/run_gate_summary.json" \
  "$exists_dir/reports/run_gate.json"
do
  [ -e "$p" ] || continue
  echo " - $(size_of "$p") bytes  $p"
done

# pick best non-empty valid JSON source
SRC="$(python3 - <<'PY'
import os, json
cands = [
  os.environ.get("C1",""),
  os.environ.get("C2",""),
  os.environ.get("C3",""),
  os.environ.get("C4",""),
]
def ok(p):
  if not p or not os.path.isfile(p): return False
  if os.path.getsize(p) < 50: return False
  try:
    with open(p,"rb") as f: b=f.read()
    json.loads(b.decode("utf-8","replace"))
    return True
  except Exception:
    return False

for p in cands:
  if ok(p):
    print(p); break
PY
)" \
C1="$exists_dir/run_gate.json" \
C2="$exists_dir/reports/run_gate_summary.json" \
C3="$exists_dir/reports/run_gate.json" \
C4="$exists_dir/run_gate_summary.json"

T_SIZE="$(size_of "$TARGET")"
echo "[TARGET]=$TARGET size=${T_SIZE}"
[ -n "${SRC:-}" ] || { echo "[ERR] cannot find any valid JSON source to fill gate summary"; exit 2; }
echo "[SRC]=$SRC"

if [ "$T_SIZE" -ge 50 ]; then
  echo "[OK] target already non-empty (>=50B). Skip overwrite."
else
  [ -f "$TARGET" ] && cp -f "$TARGET" "${TARGET}.bak_zero_${TS}" && echo "[BACKUP] ${TARGET}.bak_zero_${TS}" || true
  cp -f "$SRC" "$TARGET"
  echo "[FIXED] copied SRC -> TARGET"
fi

echo
echo "== VERIFY (GET, not HEAD): /api/vsp/run_file_allow?rid=...&path=run_gate_summary.json =="
B="$(curl -sS --max-time 6 "$BASE/api/vsp/run_file_allow?rid=$RID_GATE_ROOT&path=run_gate_summary.json" || true)"
echo "[RESP_BYTES]=$(printf %s "$B" | wc -c | tr -d ' ')"
echo "$B" | head -c 200; echo
