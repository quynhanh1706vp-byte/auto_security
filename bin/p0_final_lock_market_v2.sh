#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"

OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/FINAL_LOCK_${TS}"
REL_DIR="/home/test/Data/SECURITY_BUNDLE/out_ci/releases"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need tar; need sha256sum; need mkdir; need date; need sed; need awk; need grep

mkdir -p "$OUT"/{checks,notes}

echo "[INFO] BASE=$BASE SVC=$SVC RID=$RID"
echo "[INFO] OUT=$OUT"

echo "== [A] Commercial gate ==" | tee "$OUT/checks/gate.txt"
bash bin/p0_commercial_gate_ui_v1.sh | tee -a "$OUT/checks/gate.txt"

echo "== [B] Verify /c/* redirect targets ==" | tee "$OUT/checks/csuite_redirect.txt"
check_redirect(){
  local path="$1" exp="$2"
  # no -L: we want the 302 + Location
  local hdr; hdr="$(curl -sS -I --connect-timeout 1 --max-time 6 "$BASE$path?rid=$RID" || true)"
  local code; code="$(printf "%s" "$hdr" | awk 'NR==1{print $2}')"
  local loc; loc="$(printf "%s" "$hdr" | tr -d '\r' | awk -F': ' 'tolower($1)=="location"{print $2; exit}')"
  echo "$path code=$code location=$loc (expect $exp)" | tee -a "$OUT/checks/csuite_redirect.txt"
  [ "$code" = "302" ] || [ "$code" = "301" ] || { echo "[FAIL] $path not redirect"; exit 2; }
  # Location may include query string; only check prefix
  case "$loc" in
    "$exp"*) : ;;
    *) echo "[FAIL] $path bad Location: $loc (want prefix $exp)"; exit 2;;
  esac
}
check_redirect "/c/dashboard" "/vsp5"
check_redirect "/c/runs" "/runs"
check_redirect "/c/data_source" "/data_source"
check_redirect "/c/settings" "/settings"
check_redirect "/c/rule_overrides" "/rule_overrides"

echo "== [C] Capture release headers ==" | tee "$OUT/checks/headers.txt"
curl -sS -D "$OUT/checks/vsp5.hdr" -o /dev/null "$BASE/vsp5?rid=$RID" || true
grep -E 'X-VSP-(RELEASE|ASSET|REWRITE|PKG|SHA|RELEASE-TS)' -i "$OUT/checks/vsp5.hdr" | sed 's/\r$//' | tee -a "$OUT/checks/headers.txt" || true

echo "== [D] Market release pack ==" | tee "$OUT/checks/pack.txt"
RID="$RID" bash bin/p0_market_release_pack_v1.sh | tee -a "$OUT/checks/pack.txt"

PKG_LATEST="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/MARKET_RELEASE_LATEST.tgz"
REL_PKG="${REL_DIR}/VSP_UI_MARKET_RELEASE_LATEST.tgz"

[ -f "$PKG_LATEST" ] || { echo "[ERR] missing $PKG_LATEST"; exit 2; }
[ -f "$REL_PKG" ] || { echo "[ERR] missing $REL_PKG"; exit 2; }

echo "== [E] Proofnote (CIO) ==" | tee "$OUT/notes/PROOFNOTE.txt"
cat > "$OUT/notes/PROOFNOTE.txt" <<EOF
VSP UI COMMERCIAL FINAL LOCK
- Timestamp: $TS
- BASE: $BASE
- Service: $SVC
- RID (thin): $RID
- Behavior: thin RID auto-fallback to GLOBAL_BEST for heavy dataset (dashboard “real data”)
- /c/*: redirect (302) to canonical tabs
- Gate: GREEN

Artifacts:
- UI market release: $REL_PKG
- UI market release sha: ${REL_PKG}.sha256
EOF

echo "== [F] Index tar contents (first 80) ==" | tee "$OUT/checks/tar_list_head.txt"
tar -tzf "$REL_PKG" | head -n 80 | tee -a "$OUT/checks/tar_list_head.txt"

echo "[OK] FINAL LOCK done."
echo "Open: $BASE/vsp5?rid=$RID (Ctrl+F5 once)"
echo "Release: $REL_PKG"
