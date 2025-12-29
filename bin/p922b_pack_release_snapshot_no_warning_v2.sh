#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_ROOT="out_ci/releases"
OUT="$OUT_ROOT/RELEASE_UI_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need sha256sum; need tar; need date
need rsync


# P932_ENFORCE_P934_JS_GATE
bash bin/p934_js_syntax_gate_strict_v1.sh
echo "== [P922B] smoke =="
bash bin/p918_p0_smoke_no_error_v1.sh | tee "$OUT/p918_smoke.txt"

echo "== [P922B] collect API evidence =="
curl -fsS "$BASE/api/vsp/ops_latest_v1"     > "$OUT/ops_latest.json" || true
curl -fsS "$BASE/api/vsp/run_status_v1"     > "$OUT/run_status.json" || true
curl -fsS "$BASE/api/vsp/journal_v1?n=80"   > "$OUT/journal.json" || true
curl -fsS "$BASE/api/vsp/log_tail_v1?n=200" > "$OUT/log_tail.json" || true

# optional evidence zip endpoint (if exists)
curl -fsS -o "$OUT/evidence.zip" "$BASE/api/vsp/evidence_zip_v1" 2>/dev/null || rm -f "$OUT/evidence.zip"

python3 - <<'PY'
import json, pathlib
out=pathlib.Path("out_ci/releases").resolve()
print("[OK] releases dir:", out)
PY

echo "== [P922B] snapshot (rsync) then tar (no file-changed) =="
SNAP="/tmp/vsp_ui_snap_${TS}"
rm -rf "$SNAP"
mkdir -p "$SNAP"

# snapshot only what is needed for UI release (exclude volatile)
rsync -a --delete \
  --exclude '.git' \
  --exclude 'out_ci' \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  --exclude '*.log' \
  ./ "$SNAP/ui/"

tar -C "$SNAP" -czf "$OUT/ui_snapshot_${TS}.tgz" ui

sha256sum "$OUT/ui_snapshot_${TS}.tgz" | tee "$OUT/ui_snapshot_${TS}.sha256"

echo "== [P922B] done =="
echo "[OK] OUT=$OUT"
ls -lah "$OUT" | sed -n '1,120p'
