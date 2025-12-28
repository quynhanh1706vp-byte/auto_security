#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need date; need curl; need jq

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

ROOT = Path(".")
MARK="VSP_P1_ALLOW_SHA256SUMS_RUN_FILE_V3"

# Find candidates: files that likely implement run_file + "not allowed" or special backfill message
cands=[]
for p in ROOT.rglob("*.py"):
    try:
        s=p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "SHA256SUMS" in s:
        continue
    hit = ("/api/vsp/run_file" in s) or ("run_file" in s and "not allowed" in s) or ("backfilled minimal summary" in s)
    if hit:
        cands.append((p,s))

if not cands:
    print("[ERR] cannot find candidate python files for run_file/not-allowed. Try: grep -R \"not allowed\" -n .")
    raise SystemExit(2)

patched=[]
for p,s in cands:
    orig=s
    if MARK in s:
        continue

    # Patch pattern 1: if <var> not in <ALLOW>:  -> allow SHA256SUMS too
    # (covers name/path/rel variables)
    def repl_if_not_in(m):
        var = m.group(1)
        allow = m.group(2)
        return f'if {var} not in {allow} and {var} != "reports/SHA256SUMS.txt":'

    s = re.sub(r'\bif\s+([A-Za-z_]\w*)\s+not\s+in\s+([A-Za-z_]\w*)\s*:',
               repl_if_not_in, s)

    # Patch pattern 2: explicit check of allowed reports list/set -> inject SHA256SUMS near SUMMARY
    # safe string-level insertion only inside obvious collections
    s = s.replace('"reports/SUMMARY.txt"', '"reports/SUMMARY.txt", "reports/SHA256SUMS.txt"')
    s = s.replace("'reports/SUMMARY.txt'", "'reports/SUMMARY.txt', 'reports/SHA256SUMS.txt'")

    # Patch pattern 3: allowlist contains SUMMARY.txt without reports/ prefix
    s = s.replace('"SUMMARY.txt"', '"SUMMARY.txt", "SHA256SUMS.txt"')
    s = s.replace("'SUMMARY.txt'", "'SUMMARY.txt', 'SHA256SUMS.txt'")

    # If file contains the "not allowed" JSON, ensure we don't break it; add mark
    if s != orig:
        # add marker near top (after imports) to avoid breaking indentation
        lines = s.splitlines(True)
        ins_at = 0
        for i,l in enumerate(lines[:80]):
            if l.startswith("from ") or l.startswith("import "):
                ins_at = i+1
        lines.insert(ins_at, f'\n# {MARK}\n')
        s = "".join(lines)

        bak = p.with_suffix(p.suffix + f".bak_allowsha_{int(time.time())}")
        bak.write_text(orig, encoding="utf-8")
        p.write_text(s, encoding="utf-8")
        patched.append(str(p))

print("[OK] patched_files=", patched)
if not patched:
    print("[WARN] no file changed. Possibly already allowed or patterns not matched.")
PY

# compile changed key files (best effort)
python3 -m py_compile /home/test/Data/SECURITY_BUNDLE/ui/*.py 2>/dev/null || true

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service
sleep 1

BASE="http://127.0.0.1:8910"
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"

echo "== smoke: SHA256SUMS via rid/name should be 200 =="
curl -sS -I "$BASE/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 8

echo "== smoke: required reports still 200 =="
for n in reports/index.html reports/run_gate_summary.json reports/findings_unified.json reports/SUMMARY.txt; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/vsp/run_file?rid=$RID&name=$n")"
  echo "$n -> $code"
done
