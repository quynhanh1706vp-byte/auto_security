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

echo "== [P922] smoke =="
bash bin/p918_p0_smoke_no_error_v1.sh | tee "$OUT/p918_smoke.txt"

echo "== [P922] collect API evidence =="
curl -sS "$BASE/api/vsp/ops_latest_v1"   > "$OUT/ops_latest.json"   || true
curl -sS "$BASE/api/vsp/journal_v1?n=80" > "$OUT/journal.json"      || true
curl -sS "$BASE/api/vsp/log_tail_v1?n=120" > "$OUT/log_tail.json"   || true
curl -sS -D "$OUT/run_status.hdr" -o "$OUT/run_status.json" "$BASE/api/vsp/run_status_v1" || true

echo "== [P922] evidence.zip (if endpoint exists) =="
curl -fsS -o "$OUT/evidence.zip" "$BASE/api/vsp/evidence_zip_v1" 2>/dev/null || rm -f "$OUT/evidence.zip" || true

echo "== [P922] package =="
PKG="$OUT/VSP_UI_RELEASE_${TS}.tgz"
tar -czf "$PKG" -C "$OUT_ROOT" "RELEASE_UI_${TS}"
sha256sum "$PKG" | tee "$OUT/sha256.txt"

python3 - <<'PY'
import json, pathlib
out=pathlib.Path("out_ci/releases").glob("RELEASE_UI_*")
latest=sorted(out, key=lambda p:p.name)[-1]
print("[OK] latest release:", latest)
PY

echo "[OK] release => $PKG"
