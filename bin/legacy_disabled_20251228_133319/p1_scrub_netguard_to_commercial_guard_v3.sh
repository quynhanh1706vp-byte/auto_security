#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need find

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

ts = time.strftime("%Y%m%d_%H%M%S")

# Targets: templates + key python + static js
roots = [
  Path("templates"),
  Path("static/js"),
  Path("."),  # for gateway python (we'll filter)
]

# Exact identifiers to remap (safe, deterministic)
REPL = [
  ("VSP_P1_NETGUARD_GLOBAL_V7B", "VSP_COMMERCIAL_GLOBAL_GUARD_V1"),
  ("__vsp_p1_netguard_global_v7b", "__vsp_commercial_global_guard_v1"),
  ("__vsp_console_filtered_v7b", "__vsp_console_filtered_commercial_v1"),
  ("__vsp_p1_netguard", "__vsp_commercial_guard"),
]

# Also scrub the word "netguard" (case-insensitive) but keep meaning
def scrub_netguard_words(s: str) -> str:
  # replace standalone words or substrings safely
  return re.sub(r'netguard', 'commercial_guard', s, flags=re.I)

# File filters
def is_target(p: Path) -> bool:
  if p.suffix.lower() in (".html", ".js"):
    return True
  if p.suffix.lower() == ".py" and p.name in ("wsgi_vsp_ui_gateway.py", "vsp_demo_app.py"):
    return True
  return False

def backup(p: Path, content: str):
  bak = p.with_name(p.name + f".bak_scrub_guard_v3_{ts}")
  bak.write_text(content, encoding="utf-8")
  return bak

changed = []
scanned = 0

all_files = []
for r in roots:
  if not r.exists():
    continue
  if r.is_file() and is_target(r):
    all_files.append(r)
  elif r.is_dir():
    for p in r.rglob("*"):
      if p.is_file() and is_target(p):
        all_files.append(p)

for p in sorted(set(all_files)):
  scanned += 1
  orig = p.read_text(encoding="utf-8", errors="replace")
  s = orig
  for a,b in REPL:
    s = s.replace(a,b)
  s = scrub_netguard_words(s)

  if s != orig:
    bak = backup(p, orig)
    p.write_text(s, encoding="utf-8")
    changed.append((str(p), str(bak)))

print(f"[OK] scanned={scanned} changed={len(changed)}")
for fp,bk in changed[:40]:
  print(" -", fp)
  print("   backup:", bk)
if len(changed) > 40:
  print(" ... +", len(changed)-40, "more")
PY

echo "== post-grep (should be empty) =="
grep -RIn --exclude='*.bak_*' "VSP_P1_NETGUARD_GLOBAL_V7B\|netguard\|NETGUARD" templates static/js wsgi_vsp_ui_gateway.py vsp_demo_app.py 2>/dev/null | head -n 40 || true

echo "[DONE] scrubbed netguard markers -> commercial guard."
