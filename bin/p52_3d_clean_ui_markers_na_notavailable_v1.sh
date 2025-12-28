#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_3d_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need ls; need head; need sudo; need cp; need mkdir
command -v systemctl >/dev/null 2>&1 || true

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release"; exit 2; }
ATT="$latest_release/evidence/p52_3d_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

python3 - <<'PY'
from pathlib import Path
import re, datetime

ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
targets=[]
for root in [Path("templates"), Path("static/js")]:
    if root.exists():
        for p in root.rglob("*"):
            if p.is_file() and p.suffix.lower() in (".html",".js",".css"):
                targets.append(p)

changed=[]
for p in targets:
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s
    # Replace UI display tokens only (safe)
    s = s.replace("N/A", "—")
    s = re.sub(r"(?i)\bnot available\b", "—", s)
    if s != orig:
        bak = p.with_name(p.name + f".bak_p52_3d_{ts}")
        bak.write_text(orig, encoding="utf-8")
        p.write_text(s, encoding="utf-8")
        changed.append(str(p))

Path("out_ci").mkdir(exist_ok=True)
Path(f"out_ci/p52_3d_{ts}_changed_files.txt").write_text("\n".join(changed)+"\n", encoding="utf-8")
print("[OK] changed_files=", len(changed))
PY

# Attach list
cp -f out_ci/p52_3d_*_changed_files.txt "$EVID/" 2>/dev/null || true
sudo systemctl restart "$SVC" || true
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
echo "[DONE] P52.3d APPLIED (rerun P51.2 to confirm)"
