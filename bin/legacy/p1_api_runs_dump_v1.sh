#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
tmp="$(mktemp -d /tmp/vsp_runs_dump_XXXXXX)"; trap 'rm -rf "$tmp"' EXIT

u="$BASE/api/vsp/runs?limit=1&offset=0"
echo "== GET $u =="
curl -sS -D "$tmp/h.txt" -o "$tmp/b.bin" "$u" || true

echo "--- status line ---"
head -n 1 "$tmp/h.txt" || true
echo "--- headers (ct/location/len/enc) ---"
grep -Ei '^(content-type:|location:|content-length:|content-encoding:)' "$tmp/h.txt" || true
echo "--- body head (first 260 bytes) ---"
python3 - <<'PY'
from pathlib import Path
b=Path("'$tmp'/b.bin").read_bytes()
print(b[:260].decode("utf-8","replace"))
print("BYTES_LEN=",len(b))
PY

echo "--- json parse? ---"
python3 - <<'PY'
import json,sys
from pathlib import Path
p=Path("'$tmp'/b.bin")
t=p.read_text("utf-8","replace").strip()
if not t:
  print("NOT_JSON: empty body"); raise SystemExit(0)
try:
  j=json.loads(t)
  print("JSON_OK keys=",sorted(list(j.keys()))[:30])
except Exception as e:
  print("NOT_JSON:",type(e).__name__,str(e))
  print("HEAD=",t[:180].replace("\n","\\n"))
PY
