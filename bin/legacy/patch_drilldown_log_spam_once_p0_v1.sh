#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== PATCH DRILLDOWN LOG SPAM -> ONCE (P0 v1) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

NEEDLE="drilldown real impl accepted"

echo "== locate files with needle =="
MAP="$(mktemp)"
( grep -RIn --binary-files=without-match "$NEEDLE" templates static/js 2>/dev/null || true ) | tee "$MAP" >/dev/null

if ! grep -q "$NEEDLE" "$MAP"; then
  echo "[WARN] needle not found in templates/static/js (maybe generated elsewhere)."
  echo "[HINT] try: grep -RIn \"$NEEDLE\" . | head"
  exit 0
fi

echo "== files =="
cut -d: -f1 "$MAP" | sort -u | nl -ba

python3 - <<'PY'
import re, datetime
from pathlib import Path

needle = "drilldown real impl accepted"
ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

# wrap any console.(log|info|debug|warn|error) line that contains needle
console_re = re.compile(r'(?m)^(?P<indent>\s*)(?P<stmt>console\.(log|info|debug|warn|error)\([^\n;]*' + re.escape(needle) + r'[^\n;]*\)\s*;?)\s*$')

def patch_file(p: Path):
  s = p.read_text(encoding="utf-8", errors="replace")
  if needle not in s:
    return False

  def repl(m):
    ind = m.group("indent") or ""
    stmt = (m.group("stmt") or "").strip()
    return (
      f"{ind}try{{\n"
      f"{ind}  if(!window.__VSP_DD_ACCEPTED_ONCE){{ window.__VSP_DD_ACCEPTED_ONCE=1; {stmt} }}\n"
      f"{ind}}}catch(_e){{}}\n"
    )

  new = console_re.sub(repl, s)
  if new == s:
    # fallback: line-based wrap if regex misses
    out=[]
    changed=False
    for line in s.splitlines(True):
      if needle in line and "console." in line and "__VSP_DD_ACCEPTED_ONCE" not in line:
        ind = re.match(r"^\s*", line).group(0)
        stmt = line.strip().rstrip(";")
        out.append(f"{ind}try{{ if(!window.__VSP_DD_ACCEPTED_ONCE){{ window.__VSP_DD_ACCEPTED_ONCE=1; {stmt}; }} }}catch(_e){{}}\n")
        changed=True
      else:
        out.append(line)
    new="".join(out)
    if not changed:
      return False

  bak = p.with_suffix(p.suffix + f".bak_ddlog_once_{ts}")
  bak.write_text(s, encoding="utf-8")
  p.write_text(new, encoding="utf-8")
  print("[OK] patched", p.as_posix())
  return True

# collect targets from grep output file list (already printed by shell)
targets=set()
for base in [Path("templates"), Path("static/js")]:
  if base.exists():
    for p in base.rglob("*"):
      if p.is_file() and p.suffix in (".html", ".js"):
        targets.add(p)

patched=0
for p in sorted(targets):
  try:
    if patch_file(p):
      patched += 1
  except Exception as e:
    print("[WARN] failed", p, e)

print("[DONE] patched_files=", patched)
PY

echo "== sanity: node --check bundle (if exists) =="
if [ -f static/js/vsp_bundle_commercial_v1.js ]; then
  node --check static/js/vsp_bundle_commercial_v1.js && echo "[OK] bundle JS syntax OK"
fi

echo "== DONE =="
echo "[NEXT] restart 8910 + hard refresh Ctrl+Shift+R, confirm console no longer spams."
