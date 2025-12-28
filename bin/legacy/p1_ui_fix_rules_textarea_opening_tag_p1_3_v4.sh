#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_bundle_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_textarea_open_${TS}"
echo "[BACKUP] ${F}.bak_textarea_open_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

key = '<textarea id="rules-json"'
i = s.find(key)
if i < 0:
    raise SystemExit("[ERR] cannot find <textarea id=\"rules-json\" in bundle")

# Find end of opening tag '>' (first > after this textarea)
j = s.find(">", i)
if j < 0:
    raise SystemExit("[ERR] cannot find end '>' of rules-json textarea opening tag")

old = s[i:j+1]

# Build a clean opening tag (single-line, fully quoted style)
new = (
    '<textarea id="rules-json" spellcheck="false" '
    'style="width:100%; min-height:240px; '
    'font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; '
    'font-size:12px; padding:12px; border-radius:12px; '
    'border:1px solid rgba(255,255,255,.08); background:rgba(0,0,0,.25); '
    'color:#e6edf3; line-height:1.35;">'
)

# Replace only this opening tag
s2 = s[:i] + new + s[j+1:]

# Safety: ensure we didn't accidentally duplicate/lose the textarea id
if s2.count('id="rules-json"') != 1:
    raise SystemExit("[ERR] unexpected number of id=\"rules-json\" after patch")

p.write_text(s2, encoding="utf-8")
print("[OK] rebuilt rules-json textarea opening tag")
print("[OLD]", old[:160].replace("\n","\\n"))
print("[NEW]", new[:160])
PY

if command -v node >/dev/null 2>&1; then
  echo "== node --check $F =="
  node --check "$F"
  echo "[OK] JS parse OK"
else
  echo "[WARN] node not installed; skip parse check"
fi
