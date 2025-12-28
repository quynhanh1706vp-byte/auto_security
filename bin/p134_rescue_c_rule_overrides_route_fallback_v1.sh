#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

# find which backend file defines /c/rule_overrides
TARGET="$(
  grep -RIn --line-number --exclude='*.bak_*' --exclude='*.disabled_*' \
    --exclude-dir='static' --exclude-dir='out_ci' \
    '"/c/rule_overrides"\x27|"\x27/c/rule_overrides"\x27|/c/rule_overrides' . \
  | head -n 1 | cut -d: -f1
)"

if [ -z "${TARGET:-}" ] || [ ! -f "$TARGET" ]; then
  echo "[ERR] cannot locate backend route for /c/rule_overrides (searched repo, excluded static/out_ci)."
  echo "      Try manually: grep -RIn '/c/rule_overrides' vsp_demo_app.py wsgi_vsp_ui_gateway.py"
  exit 2
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TARGET" "${TARGET}.bak_p134_rule_overrides_fallback_${TS}"
echo "[OK] backup => ${TARGET}.bak_p134_rule_overrides_fallback_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

path = Path(sys.argv[1])
s = path.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

# ensure redirect import exists
if re.search(r'^\s*from\s+flask\s+import\s+.*\bredirect\b', s, re.M) is None:
    # try to extend an existing "from flask import ..." line
    m = re.search(r'^(from\s+flask\s+import\s+.+)$', s, re.M)
    if m:
        old = m.group(1)
        if "redirect" not in old:
            new = old.rstrip() + ", redirect"
            s = s.replace(old, new, 1)
    else:
        # insert a new import near top (after shebang/encoding/comments)
        parts = s.splitlines(True)
        insert_at = 0
        for i, ln in enumerate(parts[:50]):
            if ln.startswith("#!") or "coding" in ln or ln.strip().startswith("#"):
                insert_at = i + 1
            else:
                break
        parts.insert(insert_at, "from flask import redirect\n")
        s = "".join(parts)

lines = s.splitlines(True)

# locate decorator for /c/rule_overrides
dec_i = None
for i, ln in enumerate(lines):
    if re.search(r'@app\.(?:route|get|post|put|delete)\(\s*[\'"]/c/rule_overrides[\'"]', ln):
        dec_i = i
        break
if dec_i is None:
    # sometimes it's add_url_rule
    if re.search(r'add_url_rule\(\s*[\'"]/c/rule_overrides[\'"]', s):
        # don't try to patch complex add_url_rule in-place
        sys.stderr.write("[ERR] route uses add_url_rule; patch manually or convert to decorator.\n")
        sys.exit(3)
    sys.stderr.write("[ERR] cannot find decorator for /c/rule_overrides in file.\n")
    sys.exit(4)

# find def after decorator
def_i = None
for j in range(dec_i+1, min(dec_i+60, len(lines))):
    if re.match(r'^\s*(async\s+def|def)\s+\w+\s*\(', lines[j]):
        def_i = j
        break
if def_i is None:
    sys.stderr.write("[ERR] cannot find function definition after decorator.\n")
    sys.exit(5)

# find end of this function block (next top-level decorator/def)
indent = re.match(r'^(\s*)', lines[def_i]).group(1)
body_indent = indent + (" " * 4)

k = def_i + 1
while k < len(lines):
    ln = lines[k]
    # stop at next top-level decorator/def (same or less indentation)
    if re.match(r'^\s*@app\.', ln) and len(re.match(r'^(\s*)', ln).group(1)) <= len(indent):
        break
    if re.match(r'^\s*(async\s+def|def)\s+\w+\s*\(', ln) and len(re.match(r'^(\s*)', ln).group(1)) <= len(indent):
        break
    k += 1

new_body = [
    f"{body_indent}# [P134] Rescue: avoid blank /c/rule_overrides by falling back to legacy UI\n",
    f"{body_indent}return redirect('/rule_overrides')\n",
]

# replace everything between def line and next block
out = lines[:def_i+1] + new_body + lines[k:]
path.write_text("".join(out), encoding="utf-8")
print("[OK] patched route body to redirect('/rule_overrides') in", str(path))
PY "$TARGET"

# restart service if possible
if command -v systemctl >/dev/null 2>&1; then
  if systemctl status "$SVC" >/dev/null 2>&1; then
    sudo systemctl restart "$SVC"
    echo "[OK] restarted: $SVC"
  else
    echo "[WARN] systemd service not found: $SVC (skip restart)"
  fi
else
  echo "[WARN] no systemctl; restart your UI process manually"
fi

echo "== [SMOKE] =="
curl -sS -D- -o /dev/null "$BASE/c/rule_overrides" | head -n 20
echo "[NEXT] Open (hard refresh): $BASE/c/rule_overrides"
