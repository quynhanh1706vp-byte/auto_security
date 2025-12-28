#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56c_js_sanitize_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need cp; need mkdir

log(){ echo "[$(date +%H:%M:%S)] $*"; }

FILES=(
  "static/js/vsp_tabs4_autorid_v1.js"
  "static/js/vsp_dashboard_luxe_v1.js"
  "static/js/vsp_dashboard_consistency_patch_v1.js"
)

python3 - <<'PY'
from pathlib import Path
import re, datetime

files = [
  Path("static/js/vsp_tabs4_autorid_v1.js"),
  Path("static/js/vsp_dashboard_luxe_v1.js"),
  Path("static/js/vsp_dashboard_consistency_patch_v1.js"),
]
ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

# heuristic: JS "good start" patterns
good = re.compile(r"""^\s*(/\*|//|\(function|\(\s*\(\)\s*=>|window\.|document\.|const\s|let\s|var\s|function\s|async\s+function\s|class\s|export\s|import\s)""")

# lines that look like terminal/log garbage
garb = re.compile(r"""^\s*(\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]|\[OK\]|\[ERR\]|\[WARN\]|\[DONE\]|test@|root@|bash\s|cd\s|curl:|Node\.js|SyntaxError:|at\s+checkSyntax|try=|/vsp5\s+code=)""")

def sanitize(p: Path):
  if not p.exists():
    print("[SKIP] missing", p)
    return

  s = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

  # drop leading garbage until first good JS line
  i = 0
  while i < len(s):
    line = s[i]
    if good.search(line):
      break
    if garb.search(line) or ("127.0.0.1" in line) or re.search(r"\b20\d{6}_\d{6}\b", line):
      i += 1
      continue
    # unknown line: if it contains many non-js characters, treat as garbage too
    if re.search(r"(?:\[19|==|\$\(|\)\s*after|\bcode=\d+\b)", line):
      i += 1
      continue
    # stop if we hit something plausible
    break

  # drop trailing garbage lines
  j = len(s)
  while j > i:
    line = s[j-1]
    if garb.search(line):
      j -= 1
      continue
    # common tail junk
    if "IMPORTANT:" in line or "Evidence:" in line:
      j -= 1
      continue
    break

  if i == 0 and j == len(s):
    print("[NOCHANGE] ", p)
    return

  bak = p.with_name(p.name + f".bak_p56c_{ts}")
  bak.write_text("".join(s), encoding="utf-8")
  p.write_text("".join(s[i:j]), encoding="utf-8")
  print("[SANITIZED]", p, "drop_head=", i, "drop_tail=", len(s)-j, "bak=", bak.name)

for p in files:
  sanitize(p)
PY

ok=1
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  if node --check "$f" >/dev/null 2>"$EVID/$(basename "$f").node.err"; then
    log "[OK] node --check OK: $f"
  else
    log "[FAIL] node --check FAIL: $f"
    tail -n 40 "$EVID/$(basename "$f").node.err" || true
    ok=0
  fi
done

if [ "$ok" -ne 1 ]; then
  log "[WARN] Some files still fail. You can apply shim (P56D)."
  exit 2
fi

log "[DONE] P56C PASS. Now hard refresh browser (Ctrl+Shift+R)."
log "Evidence: $EVID"
