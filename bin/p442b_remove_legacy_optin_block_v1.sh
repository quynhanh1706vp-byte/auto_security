#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p442b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need grep; need curl; need date; need head; need sudo || true

echo "[INFO] OUT=$OUT BASE=$BASE SVC=$SVC" | tee "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, datetime

ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
tpl_root=Path("templates")
if not tpl_root.is_dir():
    raise SystemExit("[ERR] templates/ not found")

marker="VSP_P442_LEGACY_COMMON_OPTIN"
patched=0
for f in tpl_root.rglob("*.html"):
    s=f.read_text(encoding="utf-8", errors="replace")
    if marker not in s:
        continue
    orig=s
    b=f.with_suffix(f.suffix+f".bak_p442b_{ts}")
    if not b.exists():
        b.write_text(orig, encoding="utf-8", errors="replace")

    # remove the whole script block containing the marker
    s2=re.sub(r'(?is)\n?\s*<script[^>]*>\s*/\*\s*%s\s*\*/.*?</script>\s*\n?' % re.escape(marker), "\n", s)
    if s2==s:
        # fallback: delete lines around marker until </script>
        s2=re.sub(r'(?is)/\*\s*%s\s*\*/.*?</script>' % re.escape(marker), "", s)
    s=s2

    # ensure no literal vsp_c_common_v1.js remains in this template
    s=s.replace("vsp_c_common_v1.js", "vsp_c_common_v1__REMOVED.js")

    if s!=orig:
        f.write_text(s, encoding="utf-8", errors="replace")
        patched+=1

print("[OK] patched templates:", patched)
PY

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

ok=0
for i in $(seq 1 60); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] UI not reachable" | tee -a "$OUT/log.txt"; exit 1; }
echo "[OK] UI reachable" | tee -a "$OUT/log.txt"

# fetch + assert no legacy common string in HTML
curl -fsS "$BASE/c/settings" -o "$OUT/c_settings.html"
if grep -n "vsp_c_common_v1.js" "$OUT/c_settings.html" >/dev/null; then
  echo "[FAIL] still references vsp_c_common_v1.js" | tee -a "$OUT/log.txt"
  grep -n "vsp_c_common_v1.js" "$OUT/c_settings.html" | head -n 10 | tee -a "$OUT/log.txt"
  exit 1
fi
echo "[OK] /c/settings has no vsp_c_common_v1.js reference" | tee -a "$OUT/log.txt"

