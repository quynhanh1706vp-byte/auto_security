#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== VSP BUNDLE COMMERCIAL P0 (fix3) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

BUNDLE="static/js/vsp_bundle_commercial_v1.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing bundle: $BUNDLE"; exit 2; }

python3 - <<'PY'
from pathlib import Path

def fix_escaped_interp_with_backtick(s: str):
  # Replace \${ ... } -> ${ ... } ONLY when inside contains a backtick `
  # Also unescape any inner \${ ... } inside that block.
  out = []
  i = 0
  n = len(s)
  changed = 0
  while i < n:
    if s.startswith(r"\${", i):
      j = s.find("}", i+3)
      if j != -1:
        inner = s[i+3:j]
        if "`" in inner:
          inner2 = inner.replace(r"\${", "${")
          out.append("${" + inner2 + "}")
          i = j + 1
          changed += 1
          continue
    out.append(s[i])
    i += 1
  return "".join(out), changed

def patch_file(p: Path):
  txt = p.read_text(encoding="utf-8", errors="replace")
  new, changed = fix_escaped_interp_with_backtick(txt)
  if new != txt:
    bak = p.with_suffix(p.suffix + ".bak_fix3_" + TS)
    bak.write_text(txt, encoding="utf-8")
    p.write_text(new, encoding="utf-8")
    print(f"[OK] patched {p.as_posix()} blocks_fixed={changed}")
    return True
  return False

TS = __import__("datetime").datetime.now().strftime("%Y%m%d_%H%M%S")

# Patch all vsp_*.js sources + bundle (safe: only touches \${...} blocks that contain backtick)
targets = sorted(Path("static/js").glob("vsp_*.js"))
patched = 0
for p in targets:
  if patch_file(p):
    patched += 1

print("[DONE] patched_files=", patched, "total_checked=", len(targets))
PY

echo "== node --check bundle =="
if node --check "static/js/vsp_bundle_commercial_v1.js" 2>out_ci/bundle_fix3.nodecheck.err; then
  echo "[OK] bundle JS syntax OK"
  rm -f out_ci/bundle_fix3.nodecheck.err || true
else
  echo "[ERR] bundle still has syntax error:"
  cat out_ci/bundle_fix3.nodecheck.err
  # try show context around line number
  LN="$(grep -oE 'vsp_bundle_commercial_v1\.js:[0-9]+' out_ci/bundle_fix3.nodecheck.err | head -n1 | awk -F: '{print $2}')"
  if [ -n "${LN:-}" ]; then
    echo "== context around line $LN =="
    nl -ba static/js/vsp_bundle_commercial_v1.js | sed -n "$((LN-15)),$((LN+15))p" || true
  fi
  exit 3
fi

echo "== DONE (fix3) =="
echo "[NEXT] restart UI 8910 + hard refresh (Ctrl+Shift+R), then rerun selfcheck."
