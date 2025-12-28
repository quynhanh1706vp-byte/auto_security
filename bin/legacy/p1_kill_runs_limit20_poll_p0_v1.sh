#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

TS=time.strftime("%Y%m%d_%H%M%S")
MARK="VSP_P0_KILL_RUNS_LIMIT20_POLL_V1"

# Patch BOTH JS and templates because limit=20 might live in inline scripts
targets = []
targets += [Path("static/js/vsp_runs_tab_resolved_v1.js"),
            Path("static/js/vsp_bundle_commercial_v2.js"),
            Path("static/js/vsp_bundle_commercial_v1.js")]
targets += list(Path("templates").glob("*.html"))

def backup(p: Path, tag: str):
    bak = p.with_name(p.name + f".bak_{tag}_{TS}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    return bak

# Replace only for /api/vsp/runs limit=20 (avoid touching other limit=20 in UI)
rxs = [
    # exact query
    (re.compile(r'(/api/vsp/runs\?limit=)20\b'), r'\g<1>200'),
    # limit=20 somewhere after /api/vsp/runs?
    (re.compile(r'(/api/vsp/runs\?[^"\']*?\blimit=)20\b'), r'\g<1>200'),
    # string fragments like "runs?limit=20"
    (re.compile(r'(\bruns\?limit=)20\b'), r'\g<1>200'),
]

patched=[]
for p in targets:
    if not p.exists(): 
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        continue

    s0 = s
    total_n = 0
    for rx, rep in rxs:
        s, n = rx.subn(rep, s)
        total_n += n

    if total_n > 0:
        bak = backup(p, "kill_limit20")
        s = s.rstrip() + f"\n<!-- {MARK}: replaced={total_n} -->\n" if p.suffix==".html" else s.rstrip() + f"\n/* {MARK}: replaced={total_n} */\n"
        p.write_text(s, encoding="utf-8")
        patched.append((str(p), total_n, str(bak)))

print("[DONE] patched_count=", len(patched))
for fp,n,bak in patched[:40]:
    print(f"[OK] {fp}  replaced={n}  backup={bak}")
PY

# sanity check JS
for f in static/js/vsp_runs_tab_resolved_v1.js static/js/vsp_bundle_commercial_v2.js static/js/vsp_bundle_commercial_v1.js; do
  if [ -f "$f" ] && command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 3; }
  fi
done

echo "[OK] Applied. Restart UI then Ctrl+F5 /runs (expect no more /runs?limit=20 calls)."
