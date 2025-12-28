#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
RELROOT="$ROOT/out_ci/releases"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

latest_dir="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
[ -n "$latest_dir" ] || { echo "[FAIL] no RELEASE_UI_* under $RELROOT"; exit 2; }

tgz="$(ls -1 "$latest_dir"/*.tgz 2>/dev/null | head -n1 || true)"
[ -n "$tgz" ] || { echo "[FAIL] no .tgz found in $latest_dir"; exit 2; }

echo "[P525] BASE=$BASE"
echo "[P525] latest_dir=$latest_dir"
echo "[P525] tgz=$tgz"

LOG="$latest_dir/p525_verify_${TS}.log"
exec > >(tee -a "$LOG") 2>&1

echo "== [1] service readiness =="
curl -fsS "$BASE/api/healthz" >/dev/null && echo "[OK] healthz 200" || { echo "[FAIL] healthz"; exit 2; }
curl -fsS "$BASE/api/readyz"  >/dev/null && echo "[OK] readyz 200"  || { echo "[FAIL] readyz"; exit 2; }

echo "== [2] sha256 verify =="
if [ -f "$latest_dir/SHA256SUMS" ]; then
  (cd "$latest_dir" && sha256sum -c SHA256SUMS)
  echo "[OK] SHA256SUMS verified"
else
  echo "[WARN] missing SHA256SUMS -> generating"
  (cd "$latest_dir" && sha256sum "$(basename "$tgz")" > SHA256SUMS)
  echo "[OK] SHA256SUMS generated"
fi

echo "== [3] tgz contents sanity =="
need_grep=(
  "config/systemd_unit.template"
  "config/logrotate_vsp-ui.template"
  "config/production.env"
  "RELEASE_NOTES.md"
  "bin/p521_commercial_release_pack_v2.sh"
  "bin/p523_ui_commercial_gate_v1.sh"
)
missing=0
for x in "${need_grep[@]}"; do
  if tar -tzf "$tgz" | grep -q "$x"; then
    echo "[OK] has $x"
  else
    echo "[FAIL] missing $x"
    missing=1
  fi
done
[ "$missing" -eq 0 ] || { echo "[FAIL] package missing required files"; exit 2; }

echo "== [4] git professional check (notes + snapshot) =="
if [ -f "$latest_dir/RELEASE_NOTES.md" ]; then
  git_line="$(grep -nE '^-\s*Git:\s*' "$latest_dir/RELEASE_NOTES.md" || true)"
  echo "[INFO] RELEASE_NOTES git line: ${git_line:-'(none)'}"
fi
if [ -f "$latest_dir/env_snapshot.json" ]; then
  python3 - <<PY || true
import json, pathlib
p=pathlib.Path("$latest_dir/env_snapshot.json")
j=json.loads(p.read_text(encoding="utf-8", errors="replace"))
print("[INFO] env_snapshot.ts =", j.get("ts"))
print("[INFO] env_snapshot.ver =", j.get("ver"))
PY
fi

echo "== [5] customer install smoke: extract + run P523 from package =="
TMP="/tmp/VSP_UI_TEST_${TS}"
mkdir -p "$TMP"
tar -xzf "$tgz" -C "$TMP"

pkg_dir="$(find "$TMP" -maxdepth 1 -type d -name "VSP_UI_*" | head -n1 || true)"
[ -n "$pkg_dir" ] || { echo "[FAIL] cannot find extracted VSP_UI_* folder"; exit 2; }

echo "[OK] extracted => $pkg_dir"
cd "$pkg_dir"
VSP_UI_BASE="$BASE" bash bin/p523_ui_commercial_gate_v1.sh

echo "== [DONE] P525 PASS =="
echo "[EVIDENCE] $LOG"
echo "[EXTRACTED] $pkg_dir"
