#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE_URL:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need curl; need jq; need python3

RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id // empty')"
[ -n "${RID:-}" ] || { echo "[ERR] cannot get latest rid"; exit 3; }

echo "RID=$RID"

python3 - <<'PY'
import os, hashlib
from pathlib import Path
import sys

rid = os.environ.get("RID")
base_dirs = [
  Path("/home/test/Data/SECURITY_BUNDLE/out"),
  Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
  Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
]
run_dir = None
for bd in base_dirs:
    cand = bd / rid
    if cand.exists():
        run_dir = cand
        break
if run_dir is None:
    # fallback: search shallow
    for bd in base_dirs:
        if bd.exists():
            hits = list(bd.glob(rid))
            if hits:
                run_dir = hits[0]
                break
if run_dir is None:
    print(f"[ERR] cannot locate run_dir for {rid} under known out dirs", file=sys.stderr)
    sys.exit(4)

reports = run_dir / "reports"
if not reports.exists():
    print(f"[ERR] missing reports dir: {reports}", file=sys.stderr)
    sys.exit(5)

sums = reports / "SHA256SUMS.txt"
core = ["index.html", "run_gate_summary.json", "findings_unified.json", "SUMMARY.txt"]

lines=[]
for fn in core:
    p = reports / fn
    if p.exists():
        h = hashlib.sha256(p.read_bytes()).hexdigest()
        lines.append(f"{h}  {fn}")

if not lines:
    print(f"[ERR] no core report files to hash in {reports}", file=sys.stderr)
    sys.exit(6)

sums.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"[OK] wrote: {sums} (lines={len(lines)})")
PY
