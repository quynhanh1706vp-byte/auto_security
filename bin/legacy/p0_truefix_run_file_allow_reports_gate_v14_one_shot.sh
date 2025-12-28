#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ls; need awk; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [0] snapshot =="
cp -f "$W" "${W}.bak_v14_snapshot_${TS}"
echo "[BACKUP] ${W}.bak_v14_snapshot_${TS}"

echo "== [1] ensure we are on a compiling wsgi (auto-restore if needed) =="
python3 - <<'PY'
from pathlib import Path
import py_compile, sys

w = Path("wsgi_vsp_ui_gateway.py")
def comp(p:Path)->bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

if comp(w):
    print("[OK] current wsgi compiles")
    sys.exit(0)

baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
for p in baks:
    if comp(p):
        w.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print("[OK] restored from compiling backup:", p.name)
        sys.exit(0)

print("[ERR] no compiling backup found")
sys.exit(2)
PY

echo "== [2] patch the REAL handler: /api/vsp/run_file_allow => vsp_run_file_allow_v5 =="
python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# detect handler function name from add_url_rule("/api/vsp/run_file_allow", ..., FN, ...)
m = re.search(r'add_url_rule\(\s*["\']/api/vsp/run_file_allow["\']\s*,\s*["\'][^"\']+["\']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
fn = m.group(1) if m else "vsp_run_file_allow_v5"

# locate function region
mdef = re.search(r'^\s*def\s+' + re.escape(fn) + r'\s*\(', s, flags=re.M)
if not mdef:
    print("[ERR] cannot find def", fn)
    sys.exit(2)

start = mdef.start()
# prefer end marker if present
mend = re.search(r'^\s*#\s*---\s*end\s+VSP_P1_RUN_FILE_ALLOW_V5\s*---', s[mdef.end():], flags=re.M)
end = (mdef.end() + mend.start()) if mend else None

region = s[start:end] if end else s[start:]

# patch only inside this region: the contract ALLOW.update(...) line
# We rewrite ANY ALLOW.update({ ... }) that sits right after the V5 contract marker (safer than touching other ALLOW blocks)
marker = "VSP_P0_RUNFILEALLOW_CONTRACT_ALLOW_UPDATE_V5"
mi = region.find(marker)
if mi < 0:
    print("[ERR] marker not found inside handler:", marker)
    sys.exit(2)

# search forward from marker for the first ALLOW.update({...}) call
sub = region[mi:mi+2200]  # enough window
mu = re.search(r'ALLOW\.update\(\s*\{[^}]*\}\s*\)', sub, flags=re.S)
if not mu:
    print("[ERR] cannot find ALLOW.update({...}) near marker; abort to avoid breaking file")
    sys.exit(2)

old = mu.group(0)
new = "ALLOW.update({'run_manifest.json','run_evidence_index.json','reports/findings_unified.sarif','reports/run_gate_summary.json','reports/run_gate.json'})"
sub2 = sub[:mu.start()] + new + sub[mu.end():]

region2 = region[:mi] + sub2 + region[mi+len(sub):]
out = s[:start] + region2 + (s[end:] if end else "")

if out == s:
    print("[WARN] no change (already patched?)")
else:
    p.write_text(out, encoding="utf-8")
    print("[OK] patched handler", fn, "=> ALLOW now includes reports/run_gate_summary.json + reports/run_gate.json")
PY

echo "== [3] compile check =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== [4] restart =="
systemctl restart "$SVC" || true

echo "== [5] wait service =="
ok=0
for i in $(seq 1 30); do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.25
done
[ "$ok" -eq 1 ] || { echo "[ERR] service still down"; systemctl status "$SVC" --no-pager -l | sed -n '1,120p'; exit 2; }
echo "[OK] service up"

echo "== [6] sanity run_file_allow reports gate summary (must NOT be 403-not-allowed) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 60

echo
echo "[DONE] If HTTP is 200/404(file missing) => OK. If still 403 not allowed => paste the 60 lines above."
