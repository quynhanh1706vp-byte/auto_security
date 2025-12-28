#!/usr/bin/env bash
set -euo pipefail

OUT_ROOT="/home/test/Data/SECURITY_BUNDLE/out"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need ls; need head; need basename; need mkdir; need cp; need find; need sort; need awk; need curl; need jq; need python3

# pick latest VSP_CI_* (source) and latest alias VSP_CI_RUN_* (visible rid)
SRC="$(ls -1dt "$OUT_ROOT"/VSP_CI_* 2>/dev/null | head -n1 || true)"
[ -n "$SRC" ] || { echo "[ERR] no VSP_CI_* found in $OUT_ROOT"; exit 2; }
RID_SRC="$(basename "$SRC")"
RID_ALIAS="VSP_CI_RUN_${RID_SRC#VSP_CI_}"

echo "[INFO] SRC      : $SRC"
echo "[INFO] RID_ALIAS: $RID_ALIAS"

mkdir -p "$SRC/reports"

python3 - <<'PY'
from pathlib import Path
import os, re

src = Path(os.environ["SRC"])
reports = src / "reports"

# wide patterns (case-insensitive)
want = [
  ("csv", re.compile(r"(findings|finding).*(unified|merge|merged).*\.csv$", re.I)),
  ("json", re.compile(r"(findings|finding).*(unified|merge|merged).*\.json$", re.I)),
  ("sarif", re.compile(r"(findings|finding).*(unified|merge|merged).*\.sarif$", re.I)),
]

# walk but ignore huge irrelevant dirs if any
cands = {"csv": [], "json": [], "sarif": []}
for p in src.rglob("*"):
    if not p.is_file():
        continue
    name = p.name
    for ext, rx in want:
        if rx.search(name):
            try:
                sz = p.stat().st_size
            except Exception:
                sz = -1
            cands[ext].append((sz, str(p)))

def pick(ext):
    arr = sorted(cands[ext], key=lambda x: x[0], reverse=True)
    return arr[:10]

print("[CANDIDATES] top matches (by size):")
for ext in ("csv","json","sarif"):
    top = pick(ext)
    print(f"- {ext}: {len(cands[ext])} matches")
    for sz, path in top[:5]:
        print(f"    {sz:>10}  {path}")

def copy_best(ext, dest_name):
    top = pick(ext)
    if not top:
        return None
    sz, path = top[0]
    srcp = Path(path)
    dstp = reports / dest_name
    # copy bytes
    dstp.write_bytes(srcp.read_bytes())
    return (str(srcp), str(dstp), sz)

print("\n[HYDRATE] copy best -> reports/")
results = []
r = copy_best("csv", "findings_unified.csv")
if r: results.append(("csv",)+r)
r = copy_best("json", "findings_unified.json")
if r: results.append(("json",)+r)
r = copy_best("sarif", "findings_unified.sarif")
if r: results.append(("sarif",)+r)

if results:
    for ext, srcp, dstp, sz in results:
        print(f"[OK] {ext}: {srcp} -> {dstp} ({sz} bytes)")
else:
    print("[WARN] no unified findings candidates found; run may not contain unified outputs at all.")
PY
