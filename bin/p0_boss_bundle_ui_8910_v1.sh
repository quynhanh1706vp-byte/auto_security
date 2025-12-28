#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need date; need git; need curl; need jq; need python3

TS="$(date +%Y%m%d_%H%M%S)"
ROOT="out_ci/BOSS_BUNDLE_UI_${TS}"
mkdir -p "$ROOT/proof" "$ROOT/snap"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "[INFO] BASE=$BASE"
echo "[INFO] ROOT=$ROOT"

# 1) metadata
git rev-parse --short HEAD > "$ROOT/proof/git_head.txt" || true
git status -sb > "$ROOT/proof/git_status.txt" || true

# 2) smoke proof
( curl -sS -I "$BASE/"       | sed -n '1,18p' ) > "$ROOT/proof/http_root_headers.txt" || true
( curl -sS -I "$BASE/vsp5"   | sed -n '1,18p' ) > "$ROOT/proof/http_vsp5_headers.txt" || true
( curl -sS "$BASE/api/vsp/runs?limit=1" | jq . ) > "$ROOT/proof/runs_limit1.json" || true

RID="$(jq -r '.rid_latest // .items[0].run_id // empty' "$ROOT/proof/runs_limit1.json" 2>/dev/null || true)"
echo "$RID" > "$ROOT/proof/rid_latest.txt"
echo "[INFO] rid_latest=$RID"

# 3) export proof (CSV/TGZ/SHA) if RID available
if [ -n "$RID" ]; then
  curl -sS -I "$BASE/api/vsp/export_csv?rid=${RID}" | sed -n '1,22p' > "$ROOT/proof/export_csv_headers.txt" || true
  curl -sS -I "$BASE/api/vsp/export_tgz?rid=${RID}&scope=reports" | sed -n '1,22p' > "$ROOT/proof/export_tgz_headers.txt" || true
  curl -sS "$BASE/api/vsp/sha256?rid=${RID}&name=reports/run_gate_summary.json" | jq . > "$ROOT/proof/sha256_run_gate_summary.json" || true
else
  echo "[WARN] no RID found in runs response; skip export proof" | tee "$ROOT/proof/export_warn.txt"
fi

# 4) attach recent logs if exist
for f in out_ci/ui_8910.boot.log out_ci/ui_8910.access.log out_ci/ui_8910.error.log nohup.out; do
  [ -f "$f" ] && cp -f "$f" "$ROOT/proof/" || true
done

# 5) attach key scripts (minimal snapshot)
for f in \
  wsgi_vsp_ui_gateway.py \
  bin/p1_ui_8910_single_owner_start_v2.sh \
  bin/p0_commercial_selfcheck_ui_v1.sh \
  bin/p1_fast_verify_5tabs_content_p1_v1.sh \
; do
  [ -f "$f" ] && cp -f "$f" "$ROOT/snap/" || true
done

# 6) pack
OUTZIP="out_ci/BOSS_BUNDLE_UI_${TS}.zip"
python3 - <<PY
import zipfile, os
root="${ROOT}"
out="${OUTZIP}"
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for base, _, files in os.walk(root):
        for fn in files:
            p=os.path.join(base, fn)
            arc=os.path.relpath(p, os.path.dirname(root))
            z.write(p, arc)
print("[OK] wrote:", out)
PY

ln -sfn "$(basename "$OUTZIP")" out_ci/BOSS_BUNDLE_UI_LATEST.zip
echo "[OK] latest -> out_ci/BOSS_BUNDLE_UI_LATEST.zip"
