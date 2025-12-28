#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== PATCH TEMPLATES -> BUNDLE V2 ONLY (P0 v2) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

B="static/js/vsp_bundle_commercial_v2.js"
[ -f "$B" ] || { echo "[ERR] missing bundle v2: $B"; exit 2; }

python3 - <<'PY'
from pathlib import Path
import re, datetime

tpl_dir = Path("templates")
if not tpl_dir.exists():
  print("[WARN] templates/ not found")
  raise SystemExit(0)

TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
bundle_tag = '<script defer src="/static/js/vsp_bundle_commercial_v2.js?v={{ asset_v }}"></script>'

script_re = re.compile(r'(?is)\s*<script\b[^>]*\bsrc\s*=\s*["\']([^"\']+)["\'][^>]*>\s*</script\s*>\s*')

def is_top(txt: str) -> bool:
  low = txt.lower()
  return ("<html" in low) and ("</body" in low)

patched = 0
for tp in sorted(tpl_dir.rglob("*.html")):
  txt = tp.read_text(encoding="utf-8", errors="replace")
  if not is_top(txt):
    continue

  removed = [0]  # mutable counter -> no "nonlocal"
  def repl(m):
    src = (m.group(1) or "").strip()
    if "/static/js/vsp_" in src or "static/js/vsp_" in src:
      removed[0] += 1
      return "\n"
    return m.group(0)

  new = script_re.sub(repl, txt)

  # remove any existing bundle v2 tag (we insert exactly once)
  new = re.sub(r'(?is)\s*<script\b[^>]*vsp_bundle_commercial_v2\.js[^>]*>\s*</script\s*>\s*', "\n", new)

  # insert bundle v2 exactly once before </body>
  if re.search(r"(?is)</body\s*>", new):
    new = re.sub(r"(?is)</body\s*>", "\n" + bundle_tag + "\n</body>", new, count=1)
  else:
    new += "\n" + bundle_tag + "\n"

  if new != txt:
    bak = tp.with_suffix(tp.suffix + f".bak_bundlev2_only_{TS}")
    bak.write_text(txt, encoding="utf-8")
    tp.write_text(new, encoding="utf-8")
    print(f"[OK] patched {tp.as_posix()} removed_scripts={removed[0]}")
    patched += 1

print("[DONE] templates_patched=", patched)
PY

echo "== DONE =="
echo "[NEXT] restart 8910 + HARD refresh Ctrl+Shift+R"
