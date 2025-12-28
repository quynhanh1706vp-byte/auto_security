#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need mkdir; need cp; need tar; need sha256sum; need python3; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
REL_DIR="releases/RELEASE_UI_COMMERCIAL_${TS}"
mkdir -p "$REL_DIR"

echo "== [1] Run smoke audit =="
bash bin/p2_ui_commercial_smoke_audit_v1.sh | tee "$REL_DIR/smoke_audit.log" || true

echo "== [2] Capture key versions =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin)["rid"])' 2>/dev/null || echo "")"
echo "RID=$RID" | tee "$REL_DIR/rid.txt"

echo "== [3] Snapshot core UI assets =="
mkdir -p "$REL_DIR/ui"
cp -f wsgi_vsp_ui_gateway.py "$REL_DIR/ui/" || true
cp -f vsp_demo_app.py "$REL_DIR/ui/" 2>/dev/null || true

mkdir -p "$REL_DIR/ui/static/js"
cp -f static/js/vsp_data_source_lazy_v1.js "$REL_DIR/ui/static/js/" || true

# list (not copy all) to keep package light; you can change later if needed
ls -1 static/js | sort > "$REL_DIR/ui/static_js_list.txt" 2>/dev/null || true
ls -1 templates 2>/dev/null | sort > "$REL_DIR/ui/templates_list.txt" || true
ls -1 bin 2>/dev/null | sort > "$REL_DIR/ui/bin_list.txt" || true

echo "== [4] Capture live HTML (for proof) =="
for p in vsp5 runs data_source settings rule_overrides; do
  curl -fsS "$BASE/$p" -o "$REL_DIR/${p}.html" || true
done

echo "== [5] Proofnote =="
cat > "$REL_DIR/PROOFNOTE.md" <<EOF
# VSP UI Commercial Release

- Timestamp: ${TS}
- Base URL: ${BASE}
- Latest RID: ${RID}

## Included
- wsgi_vsp_ui_gateway.py (gateway)
- vsp_data_source_lazy_v1.js (contract-only)
- smoke_audit.log (GREEN/AMBER/RED summary)
- captured HTML: /vsp5 /runs /data_source /settings /rule_overrides

## Acceptance (expected)
- Tabs return HTTP 200
- /api/vsp/run_file_allow findings_unified.json returns non-empty \`findings\`
- No X-VSP-RFA* debug headers
- DS lazy Cache-Control: no-store
EOF

echo "== [6] Pack tar.gz + sha256 =="
PKG="RELEASE_UI_COMMERCIAL_${TS}.tar.gz"
tar -czf "releases/${PKG}" -C "releases" "$(basename "$REL_DIR")"
sha256sum "releases/${PKG}" | tee "releases/${PKG}.sha256"

echo
echo "[OK] Release packed:"
echo " - $REL_DIR"
echo " - releases/${PKG}"
echo " - releases/${PKG}.sha256"
