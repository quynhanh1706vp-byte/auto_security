#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
N="${1:-300}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need tar; need sha256sum; need ss; need ps

# pick latest RELEASE_* (prefer your existing release dir)
REL="$(ls -1dt out_ci/RELEASE_* 2>/dev/null | head -n1 || true)"
[ -n "${REL:-}" ] || { echo "[ERR] no out_ci/RELEASE_* found"; exit 2; }

echo "== VSP FINAL RELEASE PACK P0 =="
echo "[REL]=$REL [BASE]=$BASE [N]=$N"

# sync latest audit bundle into REL
AB="$(ls -1t out_ci/AUDIT_BUNDLE_*.tgz 2>/dev/null | head -n1 || true)"
AS="$(ls -1t out_ci/AUDIT_BUNDLE_*.SHA256SUMS.txt 2>/dev/null | head -n1 || true)"
[ -n "${AB:-}" ] && cp -f "$AB" "$REL/" && echo "[OK] copied $(basename "$AB") -> $REL"
[ -n "${AS:-}" ] && cp -f "$AS" "$REL/" && echo "[OK] copied $(basename "$AS") -> $REL"

# strict stability under lock (prevents other scripts killing 8910)
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_stability_strict_lock_p0_v2.sh "$N" | tee -a "$REL/stability_strict_${N}.log"

# fix RELEASE_SHA256SUMS (v2 đã đúng)
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_release_fix_sha_p0_v2.sh "$REL"

# pack 1 tgz deliverable
OUTTGZ="out_ci/VSP_COMMERCIAL_FINAL_${TS}.tgz"
tar -C "$(dirname "$REL")" -czf "$OUTTGZ" "$(basename "$REL")"
sha256sum "$OUTTGZ" > "${OUTTGZ}.sha256"

echo "[OK] OUTTGZ=$OUTTGZ"
echo "[OK] SHA  =${OUTTGZ}.sha256"
echo "[HINT] verify:"
echo "  sha256sum -c ${OUTTGZ}.sha256"
