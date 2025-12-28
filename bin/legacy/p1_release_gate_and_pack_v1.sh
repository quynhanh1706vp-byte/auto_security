#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need tar; need sha256sum; need date; need mktemp; need python3

API_BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_ROOT="$(pwd)/out_ci/releases"
REL_DIR="${OUT_ROOT}/REL_${TS}"
mkdir -p "$REL_DIR" "$OUT_ROOT"

log(){ echo "$@" | tee -a "$REL_DIR/release.log"; }
run_step(){
  local name="$1"; shift
  log "== ${name} =="
  # capture both stdout+stderr to log
  ("$@") 2>&1 | tee -a "$REL_DIR/release.log"
}

# --- Preconditions: scripts must exist
REQ_SCRIPTS=(
  "bin/p1_fast_verify_vsp_ui_v2.sh"
  "bin/p1_fast_verify_5tabs_content_p1_v1.sh"
  "bin/p1_boss_demo_pack_and_verify_v1.sh"
  "bin/p1_export_bundle_by_rid_v1.sh"
)
for s in "${REQ_SCRIPTS[@]}"; do
  [ -x "$s" ] || { echo "[ERR] missing/ not executable: $s"; exit 2; }
done

log "[INFO] API_BASE=${API_BASE}"
RID="${1:-}"
if [ -z "${RID}" ]; then
  RID="$(curl -fsS "${API_BASE}/api/vsp/runs?limit=1" | jq -r '.items[0].run_id // empty')"
fi
[ -n "$RID" ] || { log "[ERR] cannot pick RID"; exit 3; }
log "[INFO] RID=${RID}"

# --- Gate steps
run_step "GATE-1: core endpoints P1 (fast verify)" \
  bash -lc "VSP_UI_BASE='${API_BASE}' bin/p1_fast_verify_vsp_ui_v2.sh"

run_step "GATE-2: 5 tabs + content P1" \
  bash -lc "VSP_UI_BASE='${API_BASE}' bin/p1_fast_verify_5tabs_content_p1_v1.sh"

run_step "GATE-3: boss demo (3-click + sha) + export bundle verify" \
  bash -lc "VSP_UI_BASE='${API_BASE}' bin/p1_boss_demo_pack_and_verify_v1.sh '${RID}'"

# --- Export bundle by RID (again, to ensure bundle exists for this release)
run_step "PACK-1: export bundle by RID" \
  bash -lc "VSP_UI_BASE='${API_BASE}' bin/p1_export_bundle_by_rid_v1.sh '${RID}'"

# Locate latest bundle matching RID
BUNDLE="$(ls -1t out_ci/bundles/*"${RID}"*.tgz 2>/dev/null | head -n1 || true)"
if [ -z "$BUNDLE" ]; then
  # fallback: any latest bundle
  BUNDLE="$(ls -1t out_ci/bundles/*.tgz 2>/dev/null | head -n1 || true)"
fi
[ -n "$BUNDLE" ] || { log "[ERR] cannot find bundle tgz in out_ci/bundles"; exit 4; }
log "[INFO] BUNDLE=${BUNDLE}"

# Copy bundle into release dir
cp -f "$BUNDLE" "$REL_DIR/" || true
BNAME="$(basename "$BUNDLE")"

# --- Extract bundle manifest+reports into release dir (for ISO evidence browsing)
TMP="$(mktemp -d)"
tar -xzf "$REL_DIR/$BNAME" -C "$TMP"
mkdir -p "$REL_DIR/bundle_extract"
cp -a "$TMP/." "$REL_DIR/bundle_extract/" || true
rm -rf "$TMP"

# --- Create RELEASE manifest + hashes
python3 - <<PY
import json, os, hashlib, subprocess, sys
from pathlib import Path

api="${API_BASE}"
rid="${RID}"
ts="${TS}"
rel_dir=Path("${REL_DIR}")
bundle_name="${BNAME}"

def sh(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return ""

def sha256_file(p: Path)->str:
    h=hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(1024*1024), b""):
            h.update(b)
    return h.hexdigest()

files=[]
for p in rel_dir.rglob("*"):
    if p.is_file():
        files.append({
            "path": str(p.relative_to(rel_dir)),
            "bytes": p.stat().st_size,
            "sha256": sha256_file(p)
        })

meta={
  "schema_version": "1.0",
  "product": "VSP_UI_RELEASE",
  "timestamp": ts,
  "api_base": api,
  "run_id": rid,
  "bundle_file": bundle_name,
  "git_commit": sh("git rev-parse HEAD"),
  "git_status": sh("git status --porcelain | wc -l"),
  "python": sh("python3 -V"),
  "gunicorn": sh("./.venv/bin/gunicorn --version || gunicorn --version"),
  "host": sh("hostname"),
}

out={
  "meta": meta,
  "files": files
}
(rel_dir/"release_manifest.json").write_text(json.dumps(out, indent=2), encoding="utf-8")

# write sha sums
lines=[]
for f in files:
    lines.append(f"{f['sha256']}  {f['path']}")
(rel_dir/"RELEASE_SHA256SUMS.txt").write_text("\n".join(lines)+("\n" if lines else ""), encoding="utf-8")
print("[OK] wrote: release_manifest.json + RELEASE_SHA256SUMS.txt")
PY

# --- Pack final release tgz
FINAL="${OUT_ROOT}/VSP_UI_RELEASE_${RID}.${TS}.tgz"
tar -czf "$FINAL" -C "$REL_DIR" .
sha256sum "$FINAL" | tee "${FINAL}.sha256"

log "== RESULT =="
log "PASS (RID=${RID})"
log "RELEASE_DIR=${REL_DIR}"
log "RELEASE_TGZ=${FINAL}"
log "RELEASE_SHA=${FINAL}.sha256"

echo
echo "[OK] RELEASE: $FINAL"
echo "[OK] SHA256 : $(cat "${FINAL}.sha256")"
