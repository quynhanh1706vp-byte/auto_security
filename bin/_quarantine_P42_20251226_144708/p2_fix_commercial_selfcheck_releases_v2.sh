#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="bin/commercial_selfcheck_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_relcheck_${TS}"
echo "[BACKUP] ${F}.bak_relcheck_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/commercial_selfcheck_v1.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

pat = r'echo "== \[3\] releases list has items ==".*?ok "releases list OK"\n'
m = re.search(pat, s, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot locate releases check block")

replacement = r'''echo "== [3] releases list has items =="
L="$tmp/releases.json"
if fetch_json "$BASE/api/vsp/releases" "$L"; then
  python3 - "$L" <<'PY'
import json,sys
j=json.load(open(sys.argv[1],"r",encoding="utf-8"))

# Try well-known keys first
cands=[]
for k in ("releases","items","data","rows","list"):
  v=j.get(k)
  if isinstance(v,list):
    cands.append((k,v))

# Fallback: any top-level list value
if not cands:
  for k,v in j.items():
    if isinstance(v,list):
      cands.append((k,v))

# Also handle nested "data": {"items":[...]} patterns
if not cands and isinstance(j.get("data"),dict):
  d=j["data"]
  for k in ("releases","items","rows","list"):
    v=d.get(k)
    if isinstance(v,list):
      cands.append(("data."+k,v))

if not cands:
  raise SystemExit("no list field found in /api/vsp/releases")

best_k, best_v = max(cands, key=lambda kv: len(kv[1]))
if len(best_v) < 1:
  raise SystemExit(f"no releases items (best field={best_k})")

print("OK releases count=", len(best_v), "field=", best_k)
PY
  ok "releases list OK (API)"
else
  echo "[WARN] /api/vsp/releases not usable; fallback to /releases HTML"
  n="$(curl -fsS "$BASE/releases" | grep -c 'release_download?rid=' || true)"
  if [ "${n:-0}" -lt 1 ]; then
    bad "no releases found (HTML fallback) n=$n"
  fi
  ok "releases list OK (HTML) n=$n"
fi
'''

s2 = re.sub(pat, replacement, s, count=1, flags=re.S)
p.write_text(s2, encoding="utf-8")
print("[OK] patched releases check block")
PY

bash -n "$F"
echo "[OK] syntax OK"
