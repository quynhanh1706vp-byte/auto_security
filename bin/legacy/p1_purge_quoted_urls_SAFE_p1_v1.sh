#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"
echo "[INFO] SAFE SCOPE: templates/*.html + static/js/*.js (NO gateway/venv/site-packages/out*)"

python3 - <<'PY'
from pathlib import Path
import re, sys, shutil

root = Path(".")
deny_markers = ("/.venv/", "/venv/", "/site-packages/", "/out", "/out_ci/", "/__pycache__/")

def in_deny(p: Path) -> bool:
    s = str(p).replace("\\","/")
    return any(m in s for m in deny_markers)

def list_files():
    files = []
    tdir = root / "templates"
    if tdir.is_dir():
        for p in tdir.rglob("*.html"):
            s = str(p).replace("\\","/")
            if ".bak_" in s or in_deny(p): 
                continue
            files.append(p)
    jdir = root / "static" / "js"
    if jdir.is_dir():
        for p in jdir.rglob("*.js"):
            s = str(p).replace("\\","/")
            if ".bak_" in s or in_deny(p):
                continue
            files.append(p)
    return sorted(set(files))

TS = __import__("datetime").datetime.now().strftime("%Y%m%d_%H%M%S")

def backup(p: Path, tag: str):
    b = p.with_name(p.name + f".bak_{tag}_{TS}")
    shutil.copy2(p, b)

rx_pairs = [
    (re.compile(r'"\%22(/static/[^"\'>\s]+)\%22"'), r'"\1"'),
    (re.compile(r"'\%22(/static/[^\"'>\s]+)\%22'"), r"'\1'"),
    (re.compile(r'=\%22(/static/[^"\'>\s]+)\%22'), r'="\1"'),
]

def drop_vsp4_lines(text: str, is_html: bool) -> str:
    if not is_html:
        return text
    out = []
    for line in text.splitlines(True):
        l = line.lower()
        if 'href="/vsp4"' in l or "href='/vsp4'" in l:
            continue
        if "<a" in l and "/vsp4" in l:
            continue
        out.append(line)
    return "".join(out)

files = list_files()
changed = []
total_repl = 0

for p in files:
    orig = p.read_text(encoding="utf-8", errors="replace")
    s = orig

    for rx, rep in rx_pairs:
        s2, n = rx.subn(rep, s)
        if n:
            total_repl += n
            s = s2

    s = drop_vsp4_lines(s, is_html=(p.suffix.lower()==".html"))

    if s != orig:
        backup(p, "SAFE_PURGE")
        p.write_text(s, encoding="utf-8")
        changed.append(str(p))

print(f"[OK] scanned files: {len(files)}")
print(f"[OK] total replacements: {total_repl}")
print(f"[OK] changed files: {len(changed)}")
for x in changed[:120]:
    print(" -", x)
if len(changed) > 120:
    print(f" - ... ({len(changed)-120} more)")

# post-check (allowed scope only)
def any_hit(substr: str):
    hits=[]
    for p in files:
        txt=p.read_text(encoding="utf-8", errors="replace")
        if substr in txt:
            hits.append(str(p))
    return hits

hits_22 = any_hit("%22")
hits_vsp4 = [f for f in any_hit("/vsp4")] + [f for f in any_hit("vsp_4tabs")] + [f for f in any_hit("vsp4")]

print("[CHECK] remaining '%22' hits (allowed scope):", len(hits_22))
for f in hits_22[:50]: print(" -", f)
if len(hits_22) > 50: print(" - ...")

print("[CHECK] remaining vsp4 refs (allowed scope):", len(set(hits_vsp4)))
for f in sorted(set(hits_vsp4))[:50]: print(" -", f)
if len(set(hits_vsp4)) > 50: print(" - ...")
PY

echo
echo "== GATE 1: py_compile gateway (must PASS; we do NOT modify it) =="
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo
echo "== GATE 2: node --check static/js/*.js (must PASS) =="
while IFS= read -r f; do
  node --check "$f" >/dev/null
done < <(find static/js -type f -name "*.js" -not -name "*.bak_*" | sort)
echo "[OK] node --check OK"

echo
echo "== POST: quick grep (scope-limited) =="
echo "[INFO] grep %22 in templates/ + static/js"
grep -RIn --exclude='*.bak_*' "%22" templates static/js 2>/dev/null || true
echo "[INFO] grep /vsp4 in templates/ + static/js"
grep -RIn --exclude='*.bak_*' "/vsp4" templates static/js 2>/dev/null || true

echo
echo "== RESTART (only after gates) =="
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^vsp-ui-8910\.service'; then
  sudo systemctl restart vsp-ui-8910.service
  echo "[OK] systemctl restart vsp-ui-8910.service"
else
  echo "[WARN] systemd unit not found (vsp-ui-8910.service). Skipping restart."
fi

echo "[DONE] SAFE purge + remove vsp4 links completed."
