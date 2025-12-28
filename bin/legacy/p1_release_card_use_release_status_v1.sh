#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

# find candidate JS files mentioning release_latest
CANDS="$(grep -RIl --exclude='*.bak_*' --exclude-dir='node_modules' 'release_latest' static/js | head -n 20 || true)"
[ -n "$CANDS" ] || { echo "[ERR] cannot find JS containing 'release_latest' under static/js"; exit 2; }

echo "== candidates =="
echo "$CANDS"

# pick the most likely: prefer file with "release" in name
JS="$(echo "$CANDS" | awk 'tolower($0) ~ /release/ {print; exit} END{}')"
[ -n "$JS" ] || JS="$(echo "$CANDS" | head -n1)"
echo "[PICK] $JS"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_relcard_${TS}"
echo "[BACKUP] ${JS}.bak_relcard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

js_path = Path(r"""'"$JS"'''""")
s = js_path.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_CARD_STATUS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Heuristic patch:
# - look for logic that sets badge/text based on package existence or truthy "package"
# - replace with robust status-based logic
#
# We'll inject helper:
inject = r"""
/* ===================== VSP_P1_RELEASE_CARD_STATUS_V1 ===================== */
function __vspReleaseStatusV1(j){
  try{
    if (!j) return {badge:"STALE", ok:false};
    const st = String(j.release_status||"").toUpperCase();
    const ex = (j.release_pkg_exists === true);
    if (st === "OK" || ex) return {badge:"OK", ok:true};
    return {badge:"STALE", ok:false};
  }catch(e){ return {badge:"STALE", ok:false}; }
}
/* ===================== /VSP_P1_RELEASE_CARD_STATUS_V1 ===================== */
"""

# Insert helper near top (after first IIFE / header) or at end if not found
if "VSP_P1_RELEASE_CARD_STATUS_V1" not in s:
    s = s.rstrip() + "\n\n" + inject + "\n"

# Now patch common patterns:
# 1) if (j.package) badge = "OK" else "NO PKG"
s2 = s

# Replace "NO PKG" with "STALE" if found (UI label)
s2 = re.sub(r'\bNO PKG\b', 'STALE', s2)

# Replace any direct checks like: if (j.package || j.release_pkg) ...
# We'll patch assignments to badge text in a generic way:
# Search for lines setting badge text/class based on package
patterns = [
    r'if\s*\(\s*j\.(?:package|release_pkg)\s*\)\s*\{',
    r'if\s*\(\s*\(j\.(?:package|release_pkg)\s*\|\|\s*j\.(?:package|release_pkg)\)\s*\)\s*\{',
]
hit = any(re.search(pat, s2) for pat in patterns)

if hit:
    # Replace first "if (j.release_pkg)" block opener with our status check
    s2 = re.sub(
        r'if\s*\(\s*j\.(?:package|release_pkg)\s*\)\s*\{',
        'if (__vspReleaseStatusV1(j).ok) {',
        s2,
        count=1
    )

# Also patch ternary-like "j.package ? 'OK' : 'NO PKG'"
s2 = re.sub(
    r'j\.(?:package|release_pkg)\s*\?\s*[\'"]OK[\'"]\s*:\s*[\'"](NO PKG|STALE)[\'"]',
    '__vspReleaseStatusV1(j).ok ? "OK" : "STALE"',
    s2
)

js_path.write_text(s2, encoding="utf-8")
print("[OK] patched release card logic in", js_path)
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] release card status patch applied."
