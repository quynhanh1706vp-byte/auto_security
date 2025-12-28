#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need find; need wc; need mkdir; need mv; need grep

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }

TS="$(date +%Y%m%d_%H%M%S)"
SRC="static/js"
DEST="_quarantine_static_js/QUAR_${TS}"
mkdir -p "$DEST"

echo "== [1] count suspicious files inside web-root ($SRC) =="
cnt_before="$(find "$SRC" -maxdepth 1 -type f \( \
  -name '*.bak_*' -o -name '*.BAD_*' -o -name '*.disabled_*' -o -name '*_snapshot_*' \
\) | wc -l | tr -d ' ')"
echo "count=$cnt_before"

echo "== [2] move them out of web-root to $DEST =="
moved=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  mv -f "$f" "$DEST/"
  moved=$((moved+1))
done < <(find "$SRC" -maxdepth 1 -type f \( \
  -name '*.bak_*' -o -name '*.BAD_*' -o -name '*.disabled_*' -o -name '*_snapshot_*' \
\) -print)

ok "moved=$moved"

echo "== [3] re-scan FORBIDDEN patterns in ACTIVE js only (exclude quarantined + backups) =="
grep -RIn --line-number \
  --exclude='*.bak_*' --exclude='*.BAD_*' --exclude='*.disabled_*' \
  '/api/vsp/run_file_allow\|findings_unified\.json\|/home/test/' static/js \
  | head -n 120 || true

echo "== [DONE] Now your SCAN should not be polluted by .bak_* in web-root. =="
echo "Tip: keep backups under $DEST (outside static/) only."
