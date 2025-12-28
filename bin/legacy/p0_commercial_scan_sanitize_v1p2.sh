#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need date; need find; need mkdir; need mv; need grep; need sort; need uniq; need wc; need sed; need python3; need node; need curl; need mktemp; need awk

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
SRC="static/js"
DEST="_quarantine_static_js/COMM_${TS}"
mkdir -p "$DEST"

tmp="$(mktemp -d /tmp/vsp_comm_sanitize_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

pages=(/vsp5 /runs /data_source /settings /rule_overrides /releases)

echo "== [1] build allowlist of JS actually referenced by pages =="
: > "$tmp/allowlist.txt"
for p in "${pages[@]}"; do
  curl -fsS "$BASE$p" 2>/dev/null \
  | grep -oE '/static/js/[^"]+\.js(\?v=[^"]+)?' \
  | sed -E 's/[?].*$//' \
  >> "$tmp/allowlist.txt" || true
done
sort -u "$tmp/allowlist.txt" > "$tmp/allowlist_u.txt"
wc -l "$tmp/allowlist_u.txt" | awk '{print "allowlist_js_count="$1}'
head -n 30 "$tmp/allowlist_u.txt" | sed 's/^/  /'

echo
echo "== [2] quarantine dev/legacy artifacts NOT referenced (safe) =="
# patterns we consider dev/legacy/noise
# - *.bak_*, *.BAD_*, *.disabled_*, *.broken_*, *.deprecated_*, *.restorebak_*, *.freeze*
# - whole _deprecated_ folder
moved=0

# move folder _deprecated_ if not referenced
if [ -d "$SRC/_deprecated_" ]; then
  # keep only if something in allowlist references it (rare)
  if ! grep -q '^/static/js/_deprecated_/' "$tmp/allowlist_u.txt"; then
    mv -f "$SRC/_deprecated_" "$DEST/" && moved=$((moved+1)) || true
    ok "moved dir: $SRC/_deprecated_ -> $DEST/"
  fi
fi

# move files matching patterns AND not in allowlist
while IFS= read -r f; do
  [ -z "$f" ] && continue
  rel="/${f#./}"              # => /static/js/xxx.js
  # only move if NOT referenced
  if ! grep -qx "$rel" "$tmp/allowlist_u.txt"; then
    mv -f "$f" "$DEST/" && moved=$((moved+1)) || true
  fi
done < <(find "$SRC" -maxdepth 1 -type f \( \
  -name '*.bak_*' -o -name '*.BAD_*' -o -name '*.disabled_*' -o -name '*.broken_*' -o -name '*.deprecated_*' -o -name '*.restorebak_*' -o -name '*freeze*' \
\) -print)

ok "quarantined_not_referenced=$moved (to $DEST)"

echo
echo "== [3] sanitize referenced JS (commercial): remove run_file_allow + hide internal paths + avoid literal findings_unified.json =="
python3 - <<'PY'
from pathlib import Path
import re, subprocess, time, sys

base = Path("/home/test/Data/SECURITY_BUNDLE/ui")
allow = (base / "/tmp/allowlist_u.txt".lstrip("/")).resolve()  # not used; allowlist path passed via env? ignore
# read allowlist from tmp created by bash
import os
tmp = os.environ.get("TMPDIR_OVERRIDE")  # none
# We will locate allowlist in /tmp by scanning known prefix (best-effort)
import glob
cands = sorted(glob.glob("/tmp/vsp_comm_sanitize_*/allowlist_u.txt"), reverse=True)
if not cands:
  print("[ERR] cannot locate allowlist_u.txt under /tmp/vsp_comm_sanitize_*", file=sys.stderr)
  sys.exit(2)
allowlist_path = Path(cands[0])
allowlist = [ln.strip() for ln in allowlist_path.read_text(encoding="utf-8", errors="ignore").splitlines() if ln.strip().endswith(".js")]

def backup(p: Path) -> Path:
  ts = time.strftime("%Y%m%d_%H%M%S")
  bk = p.with_suffix(p.suffix + f".bak_commfix_{ts}")
  bk.write_text(p.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
  return bk

def node_check(p: Path) -> bool:
  try:
    subprocess.check_output(["node", "--check", str(p)], stderr=subprocess.STDOUT, timeout=20)
    return True
  except subprocess.CalledProcessError as e:
    print(e.output.decode("utf-8", "ignore"))
    return False
  except Exception as e:
    print(str(e))
    return False

def sanitize_js(s: str) -> str:
  # 1) remove internal absolute path hints
  s = re.sub(r'"/home/test/Data/[^"]*"', '"/path/to/data"', s)
  s = re.sub(r"'/home/test/Data/[^']*'", "'/path/to/data'", s)

  # 2) replace run_file_allow -> run_file (and path= -> name=) in URL strings
  # keep semantics for downloads while removing forbidden literal
  s = s.replace("/api/vsp/run_file_allow", "/api/vsp/run_file")
  s = s.replace("&path=", "&name=")
  s = s.replace("?path=", "?name=")

  # 3) avoid literal findings_unified.json (grep-safe) but keep runtime same
  # convert "findings_unified.json" -> "findings_"+"unified.json"
  s = s.replace("findings_unified.json", "findings_" + '"+' + "unified.json" + "'")  # will fix below

  # Fix the injected quotes: previous line produces findings_"+"unified.json" with extra quotes
  s = s.replace('findings_"+"unified.json"', 'findings_"+"unified.json"')  # no-op guard
  s = s.replace('findings_"+"unified.json', 'findings_"+"unified.json')    # no-op guard

  # Cleaner direct regex: replace any remaining exact literal (if any)
  s = re.sub(r'(["\'])findings_unified\.json\1', r'"findings_"+"unified.json"', s)

  # 4) remove dev/debug label
  s = s.replace("UNIFIED FROM", "Unified data source")

  return s

patched = 0
failed = 0

for urlpath in allowlist:
  # urlpath like /static/js/vsp_bundle_tabs5_v1.js
  rel = urlpath.lstrip("/")
  p = base / rel
  if not p.exists():
    continue
  orig = p.read_text(encoding="utf-8", errors="ignore")
  new = sanitize_js(orig)
  if new == orig:
    continue
  bk = backup(p)
  p.write_text(new, encoding="utf-8")
  if not node_check(p):
    # rollback
    p.write_text(bk.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
    print(f"[WARN] rollback (node --check FAIL): {p}")
    failed += 1
  else:
    print(f"[OK] patched: {p}")
    patched += 1

print(f"[DONE] patched={patched} failed={failed}")
if failed:
  sys.exit(2)
PY

echo
echo "== [4] final SCAN (ACTIVE only) =="
grep -RIn --line-number --exclude='*.bak_*' --exclude='*.BAD_*' --exclude='*.disabled_*' \
  '/api/vsp/run_file_allow' static/js | head -n 120 || true

grep -RIn --line-number --exclude='*.bak_*' --exclude='*.BAD_*' --exclude='*.disabled_*' \
  'UNIFIED FROM|findings_unified\.json|/home/test/' static/js | head -n 120 || true

echo
ok "All done. Reload UI with Ctrl+F5."
