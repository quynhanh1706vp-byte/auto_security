#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import time, re

ts = time.strftime("%Y%m%d_%H%M%S")
tpldir = Path("templates")
jsname = "vsp_runs_tab_8tools_v1.js"
tag = f'<script src="/static/js/{jsname}"></script>'

if not tpldir.exists():
    print("[ERR] templates/ not found")
    raise SystemExit(2)

cands = []
for p in tpldir.rglob("*"):
    if not p.is_file():
        continue
    if p.suffix.lower() not in [".html", ".htm", ".jinja", ".jinja2"]:
        continue
    s = p.read_text(encoding="utf-8", errors="ignore")
    # Heuristic: vsp4 page or has /vsp4 links / runs hash
    if ("vsp4" in p.name.lower()) or ("/vsp4" in s) or ("#runs" in s) or ("vsp4#runs" in s):
        cands.append(p)

if not cands:
    # fallback: patch all templates that mention "Runs" tab / runs_index endpoint
    for p in tpldir.rglob("*.html"):
        s = p.read_text(encoding="utf-8", errors="ignore")
        if ("runs_index" in s) or ("Runs" in s and "vsp" in s.lower()):
            cands.append(p)

cands = list(dict.fromkeys(cands))
if not cands:
    print("[ERR] cannot find vsp4 template candidates to inject script")
    raise SystemExit(3)

patched = 0
for p in cands:
    s = p.read_text(encoding="utf-8", errors="ignore")
    if tag in s:
        continue
    # Insert before </body> if present, else append
    bkp = p.with_suffix(p.suffix + f".bak_inject_runs8_{ts}")
    bkp.write_text(s, encoding="utf-8")
    if "</body>" in s.lower():
        # case-insensitive insert
        m = re.search(r"</body\s*>", s, flags=re.I)
        if m:
            i = m.start()
            s2 = s[:i] + "\n" + tag + "\n" + s[i:]
        else:
            s2 = s + "\n" + tag + "\n"
    else:
        s2 = s + "\n" + tag + "\n"
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] injected runs8 js into: {p} (backup {bkp.name})")
    patched += 1

if patched == 0:
    print("[OK] already injected everywhere needed")
else:
    print(f"[DONE] injected count={patched}")
PY

echo "[OK] injection done. Reload UI (hard refresh) at: http://127.0.0.1:8910/vsp4#runs"
