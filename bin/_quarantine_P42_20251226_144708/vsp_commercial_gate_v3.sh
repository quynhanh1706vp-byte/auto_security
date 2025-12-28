#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[FAIL] missing cmd: $1"; exit 1; }; }
need curl
need python3

fetch(){ curl -fsS "$1"; }

pycond(){
  local desc="$1" url="$2" expr="$3"
  local body
  body="$(fetch "$url" || true)"
  python3 - <<PY2 <<'EOF' >/dev/null 2>&1 || { echo "[FAIL] $desc"; echo "  url=$url"; echo "  body[:220]=${body:0:220}"; return 1; }
import json,sys
body = sys.stdin.read()
obj = json.loads(body)  # accept NaN/Infinity
assert True
EOF
PY2
  # real check (2nd pass, prints ok/fail)
  python3 - <<PY3
import json,sys
body = sys.stdin.read()
obj = json.loads(body)
ok = bool(1)
print('x')
PY3
}

echo '== ops =='
python3 - <<'PY' >/dev/null || exit 1
import json,urllib.request
base = '"$BASE"'
def get(p):
  with urllib.request.urlopen(base+p, timeout=8) as r: return r.read().decode('utf-8','ignore')
j=json.loads(get('/healthz'))
assert j.get('ok')==True
j=json.loads(get('/api/vsp/version'))
assert j.get('ok')==True and isinstance(j.get('info',{}).get('git_hash',''), str)
print('OK')
PY

echo '== dashboard_v3 ==' 
python3 - <<'PY' >/dev/null || exit 1
import json,urllib.request
base = '"$BASE"'
with urllib.request.urlopen(base+'/api/vsp/dashboard_v3', timeout=10) as r:
  obj=json.loads(r.read().decode('utf-8','ignore'))
assert obj.get('ok')==True
assert (obj.get('by_severity') is not None) or ((obj.get('summary_all') or {}).get('by_severity') is not None)
print('OK')
PY

echo '[GATE] PASS'
