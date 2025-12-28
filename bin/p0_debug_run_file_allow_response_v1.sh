#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

RID="${1:-}"
if [ -z "${RID}" ]; then
  RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
fi
echo "RID=$RID"

tmp="$(mktemp -d /tmp/vsp_rfallow_dbg_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
echo "TMP=$tmp"

paths=(
  "reports/findings_unified.json"
  "report/findings_unified.json"
  "findings_unified.json"
  "reports/run_gate_summary.json"
  "report/run_gate_summary.json"
  "run_gate_summary.json"
)

for p in "${paths[@]}"; do
  echo
  echo "== PATH=$p =="
  url="$BASE/api/vsp/run_file_allow?rid=$RID&path=$p&limit=1"
  hdr="$tmp/hdr.txt"
  body="$tmp/body.txt"
  code="$(curl -sS -L -D "$hdr" -o "$body" -w "%{http_code}" "$url" || true)"

  echo "HTTP=$code"
  echo "-- headers (top) --"
  head -n 20 "$hdr" || true

  echo "-- body (first 240 bytes) --"
  head -c 240 "$body"; echo

  # try json parse
  python3 - <<PY || true
import json
from pathlib import Path
b=Path("$body").read_text(encoding="utf-8", errors="replace").strip()
print("body_len=", len(b))
try:
  j=json.loads(b)
  print("json_ok keys=", list(j.keys())[:20])
  if isinstance(j, dict):
    meta=j.get("meta") or {}
    print("has_findings=", isinstance(j.get("findings"), list), "findings_len=", len(j.get("findings") or []))
    print("meta_keys=", list(meta.keys())[:20])
except Exception as e:
  print("json_fail:", repr(e))
PY
done
