#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need sort; need grep; need sed; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [0] snapshot current =="
cp -f "$F" "${F}.bak_before_rescue_${TS}"
echo "[BACKUP] ${F}.bak_before_rescue_${TS}"

echo "== [1] find last GOOD backup (py_compile OK) =="
GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile

f = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(
    f.parent.glob(f.name + ".bak_*"),
    key=lambda p: p.stat().st_mtime,
    reverse=True
)

good = ""
for b in baks:
    try:
        py_compile.compile(str(b), doraise=True)
        good = str(b)
        break
    except Exception:
        continue

print(good)
PY
)"

if [ -z "$GOOD" ]; then
  echo "[ERR] cannot find any backup that py_compile OK"
  echo "      list recent backups:"
  ls -1t "${F}.bak_"* 2>/dev/null | head -n 15 || true
  exit 2
fi
echo "[GOOD] $GOOD"

echo "== [2] restore GOOD => $F =="
cp -f "$GOOD" "$F"
python3 -m py_compile "$F"
echo "[OK] restored + py_compile OK"

echo "== [3] JS safety: convert any stray '# VSP_*' lines to JS comments (bundle v2/v1) =="
python3 - <<'PY'
from pathlib import Path
import re

cands = [
  Path("static/js/vsp_bundle_commercial_v2.js"),
  Path("static/js/vsp_bundle_commercial_v1.js"),
]
for p in cands:
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    s2, n = re.subn(r'(?m)^\s*#\s*(VSP_[A-Za-z0-9_]+.*)$', r'// \1', s)
    if n:
        p.write_text(s2, encoding="utf-8")
        print("[OK] fixed hash-comment lines:", p, "n=", n)
PY

if command -v node >/dev/null 2>&1; then
  echo "== [3b] node --check bundles =="
  node --check static/js/vsp_bundle_commercial_v1.js >/dev/null 2>&1 || true
  node --check static/js/vsp_bundle_commercial_v2.js >/dev/null 2>&1 || true
fi

run_if_exists(){
  local s="$1"
  if [ -f "$s" ]; then
    echo "== [PATCH] $s =="
    bash "$s"
  else
    echo "[SKIP] missing $s"
  fi
}

echo "== [4] re-apply ONLY the patches we actually need now =="
run_if_exists "bin/p0_fix_findings_v2_wsgijson_hardlock_v1.sh"
run_if_exists "bin/p1_runs_enrich_wsgi_mw_v6.sh"
run_if_exists "bin/p1_backend_run_file_allow_gate_smart_v3_prefer_ci_nonunknown.sh"
run_if_exists "bin/p1_runs_fix_open_and_runsmeta_p1_v2.sh" || true

echo "== [5] restart UI (systemd if available) =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart vsp-ui-8910.service || true
fi

echo "== [6] verify endpoints =="
echo "--- HEAD / ---"
curl -sS -I "$BASE/" | sed -n '1,10p' || true

echo "--- GET /api/vsp/runs?limit=2 ---"
curl -sS "$BASE/api/vsp/runs?limit=2" | head -c 1400; echo

RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("items",[{}])[0].get("run_id",""))')"
echo "[RID]=$RID"

echo "--- GET /api/ui/findings_v2?rid=RID&limit=5 ---"
curl -sS -i "$BASE/api/ui/findings_v2?rid=$RID&limit=5&offset=0&q=" | sed -n '1,22p' || true

echo "--- GET /api/vsp/open ---"
curl -sS "$BASE/api/vsp/open" | head -c 400; echo

echo "--- run_file_allow smart (wrong rid + gate path) ---"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=WRONG_RID_123&path=run_gate_summary.json" | sed -n '1,18p' || true

echo
echo "[NEXT] Browser: Ctrl+F5 /vsp5 (or Incognito)."
echo "[NEXT] Clear rid cache once in console:"
echo "  localStorage.removeItem('vsp_rid_latest_v1');"
echo "  localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "[OK] rescue done"
