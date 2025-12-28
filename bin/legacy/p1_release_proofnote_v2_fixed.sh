#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need python3; need mkdir; need sha256sum; need awk; need ls

BASE="http://127.0.0.1:8910"

# 1) Fetch release_latest JSON
J="$(curl -fsS "$BASE/api/vsp/release_latest")"

# 2) Extract rid + urls + declared sha + paths
RID="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("rid",""))' <<<"$J")"
[ -n "$RID" ] || { echo "[ERR] rid missing in release_latest"; echo "$J"; exit 2; }

DL_URL="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("download_url",""))' <<<"$J")"
AUD_URL="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("audit_url",""))' <<<"$J")"
DECL_SHA="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("package_sha256",""))' <<<"$J")"
PKG_PATH="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("package_path",""))' <<<"$J")"
MAN_PATH="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("manifest_path",""))' <<<"$J")"
RUN_DIR="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("run_dir",""))' <<<"$J")"
NOTES="$(python3 -c 'import sys,json; j=json.loads(sys.stdin.read()); print(j.get("notes",""))' <<<"$J")"

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p releases
OUT="releases/PROOF_${RID}_${TS}.md"

# 3) Download ZIP to verify
ZIP="/tmp/${RID}.zip"
curl -fsS "$BASE${DL_URL}" -o "$ZIP"
ZSIZE="$(ls -l "$ZIP" | awk '{print $5}')"
ZSHA="$(sha256sum "$ZIP" | awk '{print $1}')"

# 4) Write proofnote
{
  echo "# VSP UI Release Proof"
  echo
  echo "- RID: \`$RID\`"
  echo "- Proof generated at: \`$(date -Is)\`"
  echo
  echo "## Package"
  echo "- package_path: \`$PKG_PATH\`"
  echo "- package_sha256 (declared): \`$DECL_SHA\`"
  echo "- manifest_path: \`$MAN_PATH\`"
  echo "- run_dir: \`$RUN_DIR\`"
  echo "- notes: $NOTES"
  echo
  echo "## Links"
  echo "- download_url: \`$DL_URL\`"
  echo "- audit_url: \`$AUD_URL\`"
  echo
  echo "## Verification"
  echo "- downloaded_zip: \`$ZIP\`"
  echo "- downloaded_size_bytes: \`$ZSIZE\`"
  echo "- downloaded_sha256: \`$ZSHA\`"
  echo
  if [ -n "$DECL_SHA" ]; then
    if [ "$DECL_SHA" = "$ZSHA" ]; then
      echo "- sha256_match: ✅ YES"
    else
      echo "- sha256_match: ❌ NO (declared != downloaded)"
    fi
  fi
} > "$OUT"

echo "[OK] wrote $OUT"
echo "[OK] downloaded $ZIP size=$ZSIZE sha256=$ZSHA"
echo "[SEND] Download: $DL_URL"
echo "[SEND] Audit:    $AUD_URL"
