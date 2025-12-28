#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT_DIR="${OUT_DIR:-$ROOT/out_ci/releases}"
LOG_LINES="${LOG_LINES:-800}"
EXTRA_FILES="${EXTRA_FILES:-}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need date; need tar; need gzip; need sed; need awk; need grep; need wc; need find; need python3; need curl

GIT_SHA="N/A"
if command -v git >/dev/null 2>&1 && [ -d "$ROOT/.git" ]; then
  GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo "N/A")"
fi

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"

SC="bin/p0_commercial_selfcheck_v1.sh"
[ -x "$SC" ] || { echo "[ERR] missing or not executable: $SC"; exit 2; }

SC_OUT="/tmp/vsp_p0_selfcheck_${TS}.log"
set +e
bash "$SC" | tee "$SC_OUT"
SC_RC="${PIPESTATUS[0]}"
set -e

OKC="$(grep -Eo 'OK=[0-9]+' "$SC_OUT" | tail -n1 | cut -d= -f2 || echo 0)"
WARC="$(grep -Eo 'WARN=[0-9]+' "$SC_OUT" | tail -n1 | cut -d= -f2 || echo 0)"
ERRC="$(grep -Eo 'ERR=[0-9]+' "$SC_OUT" | tail -n1 | cut -d= -f2 || echo 999)"

if [ "$SC_RC" -ne 0 ] || [ "${ERRC:-999}" -ne 0 ] || [ "${WARC:-999}" -ne 0 ]; then
  echo "[ERR] Selfcheck NOT clean. rc=$SC_RC OK=$OKC WARN=$WARC ERR=$ERRC"
  exit 3
fi
echo "[OK] Selfcheck clean: OK=$OKC WARN=$WARC ERR=$ERRC"

RID="N/A"
if curl -fsS "$BASE/api/vsp/runs?limit=1" >/tmp/vsp_runs_${TS}.json 2>/dev/null; then
  if command -v jq >/dev/null 2>&1; then
    RID="$(jq -r '.items[0].run_id // "N/A"' /tmp/vsp_runs_${TS}.json 2>/dev/null || echo N/A)"
  else
    RID="$(python3 - <<PY 2>/dev/null || true
import json
p="/tmp/vsp_runs_${TS}.json"
try:
  d=json.load(open(p,"r",encoding="utf-8"))
  print((d.get("items") or [{}])[0].get("run_id","N/A"))
except Exception:
  print("N/A")
PY
)"
  fi
fi

REL_NAME="VSP_UI_RELEASE_${TS}"
[ "$RID" != "N/A" ] && REL_NAME="VSP_UI_RELEASE_${TS}_${RID}"

WORK="/tmp/${REL_NAME}"
rm -rf "$WORK"
mkdir -p "$WORK"

copy_tree(){
  local src="$1" dst="$2"
  [ -e "$src" ] || return 0
  mkdir -p "$dst"
  rsync -a \
    --exclude='*.bak_*' \
    --exclude='*.pyc' \
    --exclude='__pycache__/' \
    --exclude='.pytest_cache/' \
    "$src" "$dst"
}

if command -v rsync >/dev/null 2>&1; then
  copy_tree "templates/" "$WORK/"
  copy_tree "static/" "$WORK/"
else
  (cd "$ROOT" && tar -cf - templates static 2>/dev/null) | (cd "$WORK" && tar -xf -)
fi

for f in "wsgi_vsp_ui_gateway.py" "vsp_demo_app.py" "requirements.txt"; do
  [ -f "$f" ] && install -m 0644 "$f" "$WORK/$f" || true
done

mkdir -p "$WORK/bin"
for f in \
  "bin/p0_commercial_selfcheck_v1.sh" \
  "bin/p1_ui_8910_single_owner_start_v2.sh" \
  "bin/p1_fast_verify_5tabs_content_p1_v1.sh" \
  ; do
  [ -f "$f" ] && install -m 0755 "$f" "$WORK/bin/$(basename "$f")" || true
done

SELF_PATH="$ROOT/bin/p0_pack_release_ui_v1.sh"
[ -f "$SELF_PATH" ] && install -m 0755 "$SELF_PATH" "$WORK/bin/$(basename "$SELF_PATH")" || true

mkdir -p "$WORK/out_ci"
install -m 0644 "$SC_OUT" "$WORK/out_ci/selfcheck_${TS}.log"

mkdir -p "$WORK/out_ci/log_tail"
for lf in "$ROOT/out_ci/ui_8910.boot.log" "$ROOT/nohup.out"; do
  if [ -f "$lf" ]; then
    bn="$(basename "$lf")"
    tail -n "$LOG_LINES" "$lf" > "$WORK/out_ci/log_tail/${bn}.tail_${LOG_LINES}.txt" || true
  fi
done

if [ -n "${EXTRA_FILES// }" ]; then
  mkdir -p "$WORK/extra"
  for ef in $EXTRA_FILES; do
    if [ -e "$ef" ]; then
      mkdir -p "$WORK/extra/$(dirname "$ef")"
      cp -a "$ef" "$WORK/extra/$ef" 2>/dev/null || true
    fi
  done
fi

cat > "$WORK/RELEASE_NOTES.md" <<MD
# VSP UI Commercial Release (P0.5)
- Timestamp : ${TS}
- Base URL  : ${BASE}
- Latest RID: ${RID}
- Git SHA   : ${GIT_SHA}
- Selfcheck : OK=${OKC} WARN=${WARC} ERR=${ERRC}
MD

TGZ="${OUT_DIR}/${REL_NAME}.tgz"
( cd /tmp && tar -czf "$TGZ" "$REL_NAME" )

SHA256_FILE="${TGZ}.sha256"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$TGZ" > "$SHA256_FILE"
else
  python3 - <<PY
import hashlib
p="${TGZ}"
h=hashlib.sha256()
with open(p,"rb") as f:
  for ch in iter(lambda: f.read(1024*1024), b""):
    h.update(ch)
open("${SHA256_FILE}","w").write(f"{h.hexdigest()}  {p}\n")
PY
fi

echo "[OK] Release pack created:"
echo " - $TGZ"
echo " - $SHA256_FILE"
echo "[HINT] To inspect: tar -tzf \"$TGZ\" | head"
