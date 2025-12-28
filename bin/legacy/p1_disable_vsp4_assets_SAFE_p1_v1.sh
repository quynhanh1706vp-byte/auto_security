#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"
echo "[INFO] SAFE SCOPE: templates/*.html + static/js/*.js only"

python3 - <<'PY'
from pathlib import Path
import shutil, sys, re

TS = __import__("datetime").datetime.now().strftime("%Y%m%d_%H%M%S")

tpl = Path("templates/vsp_4tabs_commercial_v1.html")
js1 = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
js2 = Path("static/js/vsp_ui_4tabs_commercial_v1.freeze.js")

td = Path("templates/_deprecated_")
jd = Path("static/js/_deprecated_")
td.mkdir(parents=True, exist_ok=True)
jd.mkdir(parents=True, exist_ok=True)

moved = []

def move_deprec(p: Path, dest_dir: Path):
    if not p.exists():
        return
    dst = dest_dir / (p.name + f".deprecated_{TS}")
    shutil.move(str(p), str(dst))
    moved.append((str(p), str(dst)))

for p, d in [(tpl, td), (js1, jd), (js2, jd)]:
    move_deprec(p, d)

print("[OK] moved:", len(moved))
for a,b in moved:
    print(" -", a, "->", b)

# Remove any remaining references to these asset names in templates (safe line-drop)
targets = list(Path("templates").rglob("*.html"))
for p in targets:
    s = p.read_text(encoding="utf-8", errors="replace")
    orig = s
    # drop lines referencing deprecated file names
    out=[]
    for line in s.splitlines(True):
        l=line.lower()
        if "vsp_4tabs_commercial_v1" in l or "vsp_ui_4tabs_commercial_v1" in l:
            continue
        out.append(line)
    s="".join(out)
    if s != orig:
        bak = p.with_name(p.name + f".bak_disable_vsp4_{TS}")
        shutil.copy2(p, bak)
        p.write_text(s, encoding="utf-8")
        print("[PATCH] cleaned refs in:", p)

# Post-check (exclude _deprecated_ and .bak)
def scope_files():
    files=[]
    for p in Path("templates").rglob("*.html"):
        s=str(p).replace("\\","/")
        if "/_deprecated_/" in s or ".bak_" in s: continue
        files.append(p)
    for p in Path("static/js").rglob("*.js"):
        s=str(p).replace("\\","/")
        if "/_deprecated_/" in s or ".bak_" in s: continue
        files.append(p)
    return files

files = scope_files()
needles = ["/vsp4", "vsp_4tabs_commercial_v1", "vsp_ui_4tabs_commercial_v1"]
hits=[]
for p in files:
    txt=p.read_text(encoding="utf-8", errors="replace")
    for n in needles:
        if n in txt:
            hits.append((str(p), n))
            break

print("[CHECK] remaining vsp4/4tabs refs (non-deprecated scope):", len(hits))
for f,n in hits[:80]:
    print(" -", f, "=>", n)
PY

echo
echo "[DONE] vsp4 assets deprecated."
echo "[NEXT] restart your UI using your usual launcher (no systemd unit found earlier)."
