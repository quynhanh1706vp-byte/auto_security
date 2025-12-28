#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci"
PKDIR="$OUT/UI_COMMERCIAL_PACK_${TS}"
mkdir -p "$PKDIR"/{app,templates,static/js,logs,proof}

echo "== UI COMMERCIAL PACK P0 =="
echo "[PKDIR] $PKDIR"

# (0) run selfcheck and store proof
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_commercial_selfcheck_p0_v1.sh > "$PKDIR/proof/selfcheck.txt" 2>&1 || true

# (1) core app
cp -f vsp_demo_app.py "$PKDIR/app/"
cp -f wsgi_vsp_ui_gateway.py "$PKDIR/app/" 2>/dev/null || true
cp -f requirements.txt "$PKDIR/app/" 2>/dev/null || true

# (2) templates
rsync -a --delete templates/ "$PKDIR/templates/"

# (3) static bundle (only what commercial needs)
mkdir -p "$PKDIR/static/js"
cp -f static/js/vsp_bundle_commercial_v2.js "$PKDIR/static/js/" 2>/dev/null || true
cp -f static/js/vsp_bundle_commercial_v1.js "$PKDIR/static/js/" 2>/dev/null || true

# (4) logs
for f in ui_8910.access.log ui_8910.error.log ui_8910.boot.log; do
  [ -f "$OUT/$f" ] && cp -f "$OUT/$f" "$PKDIR/logs/" || true
done

# (5) manifest + checksums
python3 - <<'PY'
import hashlib, json, os
from pathlib import Path

root = Path(os.environ["PKDIR"])
items=[]
for p in sorted(root.rglob("*")):
    if p.is_file():
        h=hashlib.sha256(p.read_bytes()).hexdigest()
        items.append({"path": str(p.relative_to(root)), "bytes": p.stat().st_size, "sha256": h})
(root/"manifest.json").write_text(json.dumps({"items": items}, indent=2), encoding="utf-8")
print("[OK] manifest.json items=", len(items))
PY

( cd "$PKDIR" && sha256sum $(find . -type f -maxdepth 5 | sort) > SHA256SUMS.txt ) || true

# (6) zip
ZIP="$OUT/UI_COMMERCIAL_PACK_${TS}.zip"
( cd "$OUT" && zip -qr "$(basename "$ZIP")" "$(basename "$PKDIR")" )
echo "[OK] zipped: $ZIP"
echo "[DONE] pack ready"
