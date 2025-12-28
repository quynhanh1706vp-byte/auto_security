#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need find; need grep; need head

TS="$(date +%Y%m%d_%H%M%S)"
OFF="/tmp/vsp_ui_notes_left_${TS}.txt"

echo "== [1] backup + patch JS/HTML (safe) =="
python3 - <<'PY'
import re, shutil, time
from pathlib import Path

ts=time.strftime("%Y%m%d_%H%M%S")
targets=[]
for base in ["static","templates"]:
    p=Path(base)
    if p.exists():
        targets += [*p.rglob("*.js"), *p.rglob("*.html")]

def backup(p: Path):
    b = p.with_suffix(p.suffix + f".bak_notes2_{ts}")
    shutil.copy2(p, b)

changed=0
for p in targets:
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s

    # remove comment-only lines containing TODO/FIXME/DEBUG
    out=[]
    for ln in s.splitlines(True):
        if re.search(r'(TODO|FIXME|DEBUG)', ln) and re.match(r'^\s*(//|/\*|\*|<!--|#)', ln):
            continue
        out.append(ln)
    s="".join(out)

    # replace common N/A placeholders in UI text
    # (avoid messing with API keys; focus on display patterns)
    s=s.replace("Run: N/A","Run: —")
    s=s.replace("RID: N/A","RID: —")
    s=s.replace("N/A","—")  # broad, but only for js/html (display layer)

    # avoid double replacement artifacts like "—/" etc: keep simple.

    if s!=orig:
        backup(p)
        p.write_text(s, encoding="utf-8")
        changed += 1

print(f"[OK] patched_files={changed} backups=*.bak_notes2_{ts}")
PY

echo
echo "== [2] remaining NOTES markers (should be near-zero) =="
# show up to 120 lines for quick triage
( grep -RIn --line-number -E 'TODO|FIXME|DEBUG|\bN/A\b|>—<|—/A' static templates 2>/dev/null || true ) \
| head -n 120 | tee "$OFF" || true

echo
echo "[DONE] leftovers list: $OFF"
