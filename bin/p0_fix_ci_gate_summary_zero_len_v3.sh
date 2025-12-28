#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need wc; need cp; need mkdir; need head

TS="$(date +%Y%m%d_%H%M%S)"

# pick latest VSP_CI_RUN_* from filesystem (NO HTTP dependency)
C1="$(ls -1dt /home/test/Data/SECURITY_BUNDLE/ui/out_ci/VSP_CI_RUN_* 2>/dev/null | head -n1 || true)"
C2="$(ls -1dt /home/test/Data/SECURITY_BUNDLE/out/VSP_CI_RUN_* 2>/dev/null | head -n1 || true)"
PICK="${C1:-${C2:-}}"
[ -n "$PICK" ] || { echo "[ERR] no VSP_CI_RUN_* found in ui/out_ci or out"; exit 2; }
RID="$(basename "$PICK")"
echo "[RID_GATE_ROOT]=$RID"

# choose run dir
D_UI="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/${RID}"
D_OUT="/home/test/Data/SECURITY_BUNDLE/out/${RID}"
RUN_DIR=""
[ -d "$D_UI" ] && RUN_DIR="$D_UI"
[ -z "$RUN_DIR" ] && [ -d "$D_OUT" ] && RUN_DIR="$D_OUT"
[ -n "$RUN_DIR" ] || { echo "[ERR] run dir missing: $D_UI or $D_OUT"; exit 2; }
echo "[RUN_DIR]=$RUN_DIR"

size_of(){ [ -f "$1" ] && wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0; }
is_json_ok(){
  python3 - <<PY >/dev/null 2>&1
import json,sys
p=sys.argv[1]
with open(p,"rb") as f:
  b=f.read()
if len(b)<2: raise SystemExit(2)
json.loads(b.decode("utf-8","replace"))
print("ok")
PY
}

ROOT="$RUN_DIR/run_gate_summary.json"
REPO="$RUN_DIR/reports/run_gate_summary.json"
ALT1="$RUN_DIR/run_gate.json"
ALT2="$RUN_DIR/reports/run_gate.json"
mkdir -p "$RUN_DIR/reports"

echo "== sizes =="
for p in "$ROOT" "$REPO" "$ALT1" "$ALT2"; do
  [ -e "$p" ] || continue
  echo " - $(size_of "$p") bytes  $p"
done

# choose best source: prefer existing valid run_gate_summary.json, else run_gate.json
SRC=""
for p in "$ROOT" "$REPO" "$ALT1" "$ALT2"; do
  [ -f "$p" ] || continue
  if is_json_ok "$p"; then SRC="$p"; break; fi
done
[ -n "$SRC" ] || { echo "[ERR] no valid JSON found among gate files"; exit 2; }
echo "[SRC]=$SRC"

# ensure both ROOT + REPO are valid & identical (copy SRC if missing/bad)
fix_one(){
  local tgt="$1"
  if [ -f "$tgt" ] && is_json_ok "$tgt"; then
    echo "[OK] json valid: $tgt"
    return 0
  fi
  [ -f "$tgt" ] && cp -f "$tgt" "${tgt}.bak_bad_${TS}" && echo "[BACKUP] ${tgt}.bak_bad_${TS}" || true
  cp -f "$SRC" "$tgt"
  echo "[FIXED] $tgt <= $SRC"
}

fix_one "$ROOT"
fix_one "$REPO"

echo
echo "== quick peek (overall/verdict) =="
python3 - <<PY
import json
p="$ROOT"
d=json.load(open(p,"r",encoding="utf-8"))
print("file=",p)
print("overall=",d.get("overall"),"verdict=",d.get("verdict"),"ts=",d.get("ts") or d.get("generated_at"))
PY
