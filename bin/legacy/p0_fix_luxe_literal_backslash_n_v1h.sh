#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || err "missing $F"

TS="$(date +%Y%m%d_%H%M%S)"
PRE="${F}.bak_pre_v1h_${TS}"
cp -f "$F" "$PRE"
ok "backup: $PRE"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

# Heuristic: if file got "stringified", it will contain lots of literal '\n' sequences.
cnt = s.count("\\n")
print("[INFO] literal \\\\n count =", cnt)

# Fix the common corruption pattern: "\n" + indentation inserted into JS as literal characters.
# Convert ONLY when followed by spaces/tabs (indent), which strongly indicates it was meant as a newline.
s2 = re.sub(r"\\n(?=[ \t]{2,})", "\n", s)

# Also handle "\n/*" or "\n(" cases that sometimes appear (no indentation but next token begins)
s2 = re.sub(r"\\n(?=[/\(\{\[])", "\n", s2)

# Clean up accidental "\n\n" literal pairs that got duplicated
s2 = s2.replace("\\n\\n", "\n\n")

# OPTIONAL: normalize CRLF remnants
s2 = s2.replace("\r\n", "\n").replace("\r", "\n")

if s2 != s:
  p.write_text(s2, encoding="utf-8")
  print("[OK] rewritten:", p)
else:
  print("[OK] no change needed")
PY

if node --check "$F"; then
  ok "node --check PASS: $F"
else
  warn "node --check FAIL: rollback"
  cp -f "$PRE" "$F"
  node --check "$F" >/dev/null 2>&1 || true
  err "rolled back. Paste node --check error line+col if still failing."
fi

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
fi

echo "== [SMOKE] show any remaining '\\n' literals near suspicious areas =="
grep -n '\\n' "$F" | head -n 20 || true

echo "== [DONE] Hard refresh browser (Ctrl+F5) and check console =="
