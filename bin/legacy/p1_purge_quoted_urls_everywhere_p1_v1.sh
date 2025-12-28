#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import time, re

roots = [Path("templates"), Path("static/js"), Path(".")]
files = []

# scan only likely files
for root in roots:
    if not root.exists(): 
        continue
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if p.name.endswith((".png",".jpg",".jpeg",".gif",".webp",".woff",".woff2",".ttf",".ico",".map",".zip",".tgz",".gz",".pdf")):
            continue
        if p.suffix.lower() not in (".html",".js",".py",".css"):
            continue
        # keep scope tight
        if "out" in p.parts and p.suffix.lower() != ".py":
            continue
        files.append(p)

# replacements that kill the %22 poison + \" noise
def fix(s: str) -> str:
    s2 = s

    # kill encoded quote in absolute base url
    s2 = s2.replace("http://127.0.0.1:8910%22/", "http://127.0.0.1:8910/")
    s2 = s2.replace("https://127.0.0.1:8910%22/", "https://127.0.0.1:8910/")

    # kill encoded quote before static
    s2 = s2.replace("%22/static/", "/static/")
    s2 = s2.replace("%22/api/", "/api/")

    # kill \" sequences in HTML attributes that accidentally shipped
    s2 = s2.replace('src=\\"', 'src="')
    s2 = s2.replace('href=\\"', 'href="')
    s2 = s2.replace('\\"/static/', '"/static/')
    s2 = s2.replace("\\'/static/", "'/static/")

    # if any JS string contains 8910\" -> 8910
    s2 = s2.replace('127.0.0.1:8910\\"', '127.0.0.1:8910')
    s2 = s2.replace('127.0.0.1:8910\\\"', '127.0.0.1:8910')
    s2 = s2.replace('127.0.0.1:8910"', '127.0.0.1:8910')
    s2 = s2.replace("127.0.0.1:8910'", "127.0.0.1:8910")

    return s2

patched = 0
hits = []
for p in files:
    s = p.read_text(encoding="utf-8", errors="replace")
    if ("%22" not in s) and ('src=\\"' not in s) and ('href=\\"' not in s) and ('8910\\"' not in s) and ('8910\\\"' not in s):
        continue
    s2 = fix(s)
    if s2 != s:
        bak = Path(str(p) + f".bak_purgeq_{int(time.time())}")
        bak.write_text(s, encoding="utf-8")
        p.write_text(s2, encoding="utf-8")
        patched += 1
        hits.append(str(p))

print("[OK] patched files:", patched)
for h in hits[:30]:
    print(" -", h)
if patched > 30:
    print(" - ...", patched-30, "more")
PY

echo "[NEXT] restart"
