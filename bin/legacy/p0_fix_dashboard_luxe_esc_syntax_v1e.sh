#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || err "missing $F"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixesc_${TS}"
ok "backup: ${F}.bak_fixesc_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

needle = "function esc("
i = s.find(needle)
if i < 0:
  raise SystemExit("[ERR] cannot find function esc(")

# find function block by brace matching
j = s.find("{", i)
if j < 0:
  raise SystemExit("[ERR] cannot find '{' for esc()")

depth = 0
k = j
while k < len(s):
  ch = s[k]
  if ch == "{":
    depth += 1
  elif ch == "}":
    depth -= 1
    if depth == 0:
      k += 1  # include closing brace
      break
  k += 1

if depth != 0:
  raise SystemExit("[ERR] brace mismatch while parsing esc()")

safe_esc = r'''function esc(s){
  try{
    return (s==null ? "" : String(s))
      .replace(/&/g,"&amp;")
      .replace(/</g,"&lt;")
      .replace(/>/g,"&gt;")
      .replace(/"/g,"&quot;");
  }catch(e){
    return "";
  }
}'''

ns = s[:i] + safe_esc + s[k:]
p.write_text(ns, encoding="utf-8")
print("[OK] replaced esc() block:", i, "->", k)
PY

node --check "$F" && ok "node --check OK: $F" || err "node --check FAIL: $F"

# optional: restart service if used
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
fi

echo "== [DONE] Reload /vsp5 and confirm console is clean =="
