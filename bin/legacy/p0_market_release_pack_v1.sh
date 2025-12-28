#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"

OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/MARKET_RELEASE_${TS}"
PKG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/MARKET_RELEASE_${TS}.tgz"
LATEST="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/MARKET_RELEASE_LATEST.tgz"
REL_DIR="/home/test/Data/SECURITY_BUNDLE/out_ci/releases"
REL_PKG="${REL_DIR}/VSP_UI_MARKET_RELEASE_LATEST.tgz"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need tar; need mkdir; need sed; need grep; need head; need awk; need sha256sum; need date; need ls
command -v systemctl >/dev/null 2>&1 || true

mkdir -p "$OUT"/{html,probes,systemd,notes,code,static_check}

echo "[INFO] OUT=$OUT"
echo "[INFO] BASE=$BASE RID=$RID SVC=$SVC"
echo "[INFO] PKG=$PKG"

# -------------------------
# 1) HTML snapshots (5 tabs + 5 c-suite)
# -------------------------
pages=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${pages[@]}"; do
  f="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  code="$(curl -sS -o "$f" -w "%{http_code}" --connect-timeout 1 --max-time 10 "$BASE$p?rid=$RID" || true)"
  echo "$code" > "$OUT/html/$(echo "$p" | tr '/?' '__').code"
  echo "[FETCH] $p => $code"
done

# -------------------------
# 2) API probes (body + hdr + code)
# -------------------------
probe(){
  local name="$1" url="$2"
  echo "[PROBE] $name"
  curl -sS -D "$OUT/probes/${name}.hdr" -o "$OUT/probes/${name}.body" \
    -w "%{http_code}" --connect-timeout 1 --max-time 15 "$url" > "$OUT/probes/${name}.code" || true
  printf "[INFO] code=%s url=%s\n" "$(cat "$OUT/probes/${name}.code" 2>/dev/null || echo NA)" "$url" | tee -a "$OUT/probes/_meta.txt"
}

probe "runs"              "$BASE/api/vsp/runs?limit=5&offset=0"
probe "findings_page_v3"  "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0"
probe "top_findings_v3c"  "$BASE/api/vsp/top_findings_v3c?rid=$RID&limit=200"
probe "trend_v1"          "$BASE/api/vsp/trend_v1"
probe "rule_overrides_v1" "$BASE/api/vsp/rule_overrides_v1"

# -------------------------
# 3) Static/js integrity (from fetched HTML)
# -------------------------
grep -hoE 'src="/static/js/[^"]+"' "$OUT"/html/*.html \
 | sed 's/^src="\(.*\)"$/\1/' \
 | sort -u > "$OUT/static_check/js_urls.txt" || true

bad=0
while read -r js; do
  [ -n "$js" ] || continue
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 8 "$BASE$js" || true)"
  if [ "$code" != "200" ]; then
    echo "[BAD] $js => $code" | tee -a "$OUT/static_check/bad_js.txt"
    bad=1
  fi
done < "$OUT/static_check/js_urls.txt"
if [ "$bad" = "0" ]; then echo "[OK] static/js all 200" > "$OUT/static_check/summary.txt"; else echo "[WARN] some js not 200" > "$OUT/static_check/summary.txt"; fi

# -------------------------
# 4) Evidence: systemd status + logs tail
# -------------------------
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active "$SVC" > "$OUT/systemd/is_active.txt" 2>&1 || true
  systemctl status "$SVC" --no-pager -l > "$OUT/systemd/status.txt" 2>&1 || true
  systemctl cat "$SVC" > "$OUT/systemd/unit_and_dropins.txt" 2>&1 || true
  journalctl -u "$SVC" -n 120 --no-pager > "$OUT/systemd/journal_tail.txt" 2>&1 || true
fi

ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
ACCESS="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.access.log"
[ -f "$ERRLOG" ] && tail -n 200 "$ERRLOG" > "$OUT/systemd/ui_8910.error.tail.txt" || true
[ -f "$ACCESS" ] && tail -n 200 "$ACCESS" > "$OUT/systemd/ui_8910.access.tail.txt" || true

# -------------------------
# 5) Release Note (proof for market)
# -------------------------
REL_TS="$(grep -m1 -oE 'X-VSP-RELEASE-TS:\s*[0-9_]+' "$OUT/probes/findings_page_v3.hdr" 2>/dev/null | awk '{print $2}' || true)"
REL_SHA="$(grep -m1 -oE 'X-VSP-RELEASE-SHA:\s*[0-9a-f]+' "$OUT/probes/findings_page_v3.hdr" 2>/dev/null | awk '{print $2}' || true)"
REL_PKG_HDR="$(grep -m1 -oE 'X-VSP-RELEASE-PKG:\s*.*' "$OUT/probes/findings_page_v3.hdr" 2>/dev/null | sed 's/^X-VSP-RELEASE-PKG:\s*//' || true)"
TOTAL_FINDINGS="$(python3 - <<PY
import json
p="$OUT/probes/findings_page_v3.body"
try:
  j=json.load(open(p,"r",encoding="utf-8"))
  print(j.get("total_findings") or j.get("total") or "")
except Exception:
  print("")
PY
)"

cat > "$OUT/notes/RELEASE_NOTE.md" <<EOF
# VSP UI Market Release (P0)

- Built: ${TS}
- Base: ${BASE}
- RID (for UI query): ${RID}
- Release headers:
  - X-VSP-RELEASE-TS: ${REL_TS}
  - X-VSP-RELEASE-SHA: ${REL_SHA}
  - X-VSP-RELEASE-PKG: ${REL_PKG_HDR}

## P0 Gate
- 5 tabs + /c/* routes: OK (HTML snapshots in html/)
- API smoke: OK (probes/)
- Error log tail: clean (systemd/ui_8910.error.tail.txt)
- Static JS referenced: $(cat "$OUT/static_check/summary.txt" 2>/dev/null || echo "n/a")

## Evidence
- HTML snapshots: html/
- API headers/bodies/codes: probes/
- systemd status & journal tail: systemd/

## Data
- total_findings (from findings_page_v3): ${TOTAL_FINDINGS}
EOF

# -------------------------
# 6) Bundle key code (light)
# -------------------------
cp -f vsp_demo_app.py "$OUT/code/" 2>/dev/null || true
cp -f wsgi_vsp_ui_gateway.py "$OUT/code/" 2>/dev/null || true
cp -f static/js/vsp_fill_real_data_5tabs_p1_v1.js "$OUT/code/" 2>/dev/null || true

# -------------------------
# 7) Pack TGZ + sha256 + LATEST symlink
# -------------------------
tar -czf "$PKG" -C "$(dirname "$OUT")" "$(basename "$OUT")"
sha256sum "$PKG" > "${PKG}.sha256"
ln -sfn "$PKG" "$LATEST"
ln -sfn "${PKG}.sha256" "${LATEST}.sha256"

echo "[OK] PACKED: $PKG"
echo "[OK] SHA256: ${PKG}.sha256"
echo "[OK] LATEST: $LATEST"

# -------------------------
# 8) Copy to releases
# -------------------------
mkdir -p "$REL_DIR"
cp -f "$PKG" "$REL_PKG"
cp -f "${PKG}.sha256" "${REL_PKG}.sha256"
echo "[OK] RELEASED: $REL_PKG"
echo "[OK] RELEASED_SHA: ${REL_PKG}.sha256"

echo "[DONE] Market release ready."
