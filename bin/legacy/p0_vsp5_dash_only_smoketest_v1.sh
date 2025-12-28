#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_dash_only_v1.js"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need node; need grep; need wc

echo "== [0] JS syntax =="
node --check "$JS"
echo "[OK] node --check passed"

echo "== [1] /vsp5 references dash-only JS =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dash_only_v1.js" | head -n 3 || { echo "[ERR] /vsp5 not loading vsp_dash_only_v1.js"; exit 2; }
echo "[OK] /vsp5 loads dash-only JS"

echo "== [2] rid_latest_gate_root =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin)["rid"])')"
echo "[OK] RID=$RID"

echo "== [3] run_gate_summary.json bytes + keys =="
OUT="/tmp/run_gate_summary.$RID.json"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" -o "$OUT"
echo "bytes=$(wc -c < "$OUT")"
python3 - <<PY
import json
j=json.load(open("$OUT","r",encoding="utf-8"))
print("overall=", j.get("overall"))
print("counts_total keys=", sorted((j.get("counts_total") or {}).keys()))
print("by_tool keys=", sorted((j.get("by_tool") or {}).keys()))
PY

echo "== [4] findings_unified.json HEAD (should be fetchable) =="
FOUT="/tmp/findings_unified.$RID.json"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json" -o "$FOUT" || {
  echo "[ERR] cannot fetch findings_unified.json (blocked by allowlist or missing file)"
  exit 2
}
echo "bytes=$(wc -c < "$FOUT")"
python3 - <<PY
import json
j=json.load(open("$FOUT","r",encoding="utf-8"))
arr = j.get("findings") or []
print("findings_len=", len(arr))
if arr:
  x=arr[0]
  print("sample keys=", sorted(list(x.keys()))[:12])
PY

echo "[DONE] If all OK: open /vsp5, hard refresh, click 'Load top findings (25)' and it must render rows."
