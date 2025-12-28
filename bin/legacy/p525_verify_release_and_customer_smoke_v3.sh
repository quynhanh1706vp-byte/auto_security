#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# [P545_REPAIR_P525V3_V1] fix RELROOT nounset + fix tgz picking + accept optional TGZ arg
RELROOT="${RELROOT:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

TGZ_ARG="${1:-}"
if [ -n "$TGZ_ARG" ]; then
  if [ -f "$TGZ_ARG" ]; then
    TGZ_ARG="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$TGZ_ARG")"
  else
    echo "[WARN] TGZ_ARG provided but not found: $TGZ_ARG (fallback to latest)" >&2
    TGZ_ARG=""
  fi
fi

latest_dir="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
[ -n "$latest_dir" ] || { echo "[FAIL] no RELEASE_UI_* under $RELROOT"; exit 2; }

tgz="$(ls -1 "$latest_dir"/*.tgz 2>/dev/null | head -n1 || true)"
tgz="${TGZ_ARG:-$tgz}"
[ -n "$tgz" ] || { echo "[FAIL] no .tgz found in $latest_dir"; exit 2; }


echo "[P525v3] BASE=$BASE"
echo "[P525v3] latest_dir=$latest_dir"
echo "[P525v3] tgz=$tgz"

LOG="$latest_dir/p525v3_verify_${TS}.log"
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

echo "== [3] detect tgz root + contract check =="
ROOTNAME="$(
python3 - <<PY
import tarfile, sys
tgz="$tgz"
need_rel = [
  "config/systemd_unit.template",
  "config/logrotate_vsp-ui.template",
  "config/production.env",
  "RELEASE_NOTES.md",
  "bin/p523_ui_commercial_gate_v1.sh",
]
with tarfile.open(tgz, "r:gz") as tf:
    names=tf.getnames()
    roots=set(n.split("/",1)[0] for n in names if "/" in n and not n.startswith("./"))
    root=sorted(roots)[0] if roots else ""
    print(root)
    s=set(names)
    missing=[]
    for rel in need_rel:
        ok = (rel in s) or (root and f"{root}/{rel}" in s) or (f"./{rel}" in s) or (root and f"./{root}/{rel}" in s)
        if not ok: missing.append(rel)
    if missing:
        print("MISSING:" + ",".join(missing), file=sys.stderr)
        sys.exit(2)
PY
)"
[ -n "$ROOTNAME" ] || { echo "[FAIL] cannot detect tgz root"; exit 2; }
echo "[OK] detected_root=$ROOTNAME (contract satisfied)"

echo "== [4] customer install smoke: extract + run P523 from exact root dir =="
TMP="/tmp/VSP_UI_TEST_${TS}"
mkdir -p "$TMP"
tar -xzf "$tgz" -C "$TMP"

pkg_dir="$TMP/$ROOTNAME"
[ -d "$pkg_dir" ] || { echo "[FAIL] extracted dir not found: $pkg_dir"; ls -lah "$TMP"; exit 2; }

echo "[OK] extracted => $pkg_dir"
cd "$pkg_dir"

[ -x "bin/p523_ui_commercial_gate_v1.sh" ] || { echo "[FAIL] missing p523 in extracted package"; ls -lah bin | head; exit 2; }

VSP_UI_BASE="$BASE" bash bin/p523_ui_commercial_gate_v1.sh

echo "== [DONE] P525v3 PASS =="
echo "[EVIDENCE] $LOG"
echo "[EXTRACTED] $pkg_dir"
