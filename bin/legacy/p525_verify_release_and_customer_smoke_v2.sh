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

echo "[P525v2] BASE=$BASE"
echo "[P525v2] latest_dir=$latest_dir"
echo "[P525v2] tgz=$tgz"

LOG="$latest_dir/p525v2_verify_${TS}.log"
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

echo "== [3] tgz contents sanity (python tarfile, prefix-safe) =="
python3 - <<PY
import tarfile, os, sys
tgz = "$tgz"
need_rel = [
  "config/systemd_unit.template",
  "config/logrotate_vsp-ui.template",
  "config/production.env",
  "RELEASE_NOTES.md",
  "bin/p523_ui_commercial_gate_v1.sh",
  # optional but nice-to-have:
  # "bin/p521_commercial_release_pack_v2.sh",
]
with tarfile.open(tgz, "r:gz") as tf:
    names = tf.getnames()
    # detect top-level folder (pkg root)
    roots = set(n.split("/",1)[0] for n in names if "/" in n and not n.startswith("./"))
    root = sorted(roots)[0] if roots else ""
    print("[INFO] detected_root =", root if root else "(none)")
    s = set(names)
    missing = []
    for rel in need_rel:
        ok = (rel in s) or (root and f"{root}/{rel}" in s) or (f"./{rel}" in s) or (root and f"./{root}/{rel}" in s)
        if ok:
            print("[OK] has", rel)
        else:
            missing.append(rel)
    if missing:
        print("[FAIL] missing:")
        for m in missing: print(" -", m)
        # show a hint list
        print("== hint: sample archive entries ==")
        for n in names[:60]: print(n)
        sys.exit(2)
print("[OK] tgz contract satisfied")
PY

echo "== [4] customer install smoke: extract + run P523 from package =="
TMP="/tmp/VSP_UI_TEST_${TS}"
mkdir -p "$TMP"
tar -xzf "$tgz" -C "$TMP"

pkg_dir="$(find "$TMP" -maxdepth 1 -type d -name "VSP_UI_*" | head -n1 || true)"
[ -n "$pkg_dir" ] || { echo "[FAIL] cannot find extracted VSP_UI_* folder"; exit 2; }

echo "[OK] extracted => $pkg_dir"
cd "$pkg_dir"
VSP_UI_BASE="$BASE" bash bin/p523_ui_commercial_gate_v1.sh

echo "== [DONE] P525v2 PASS =="
echo "[EVIDENCE] $LOG"
echo "[EXTRACTED] $pkg_dir"
