#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need date; need curl; need jq; need awk; need sed

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixruns_sha_${TS}"
echo "[BACKUP] ${F}.bak_fixruns_sha_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_FIX_RUNS_AND_SHA256SUMS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

orig=s

# (1) Fix the TypeError: run_file_url(rid, summary, sha) -> two separate calls
pat = re.compile(
    r'(?m)^(?P<ind>\s*)has\["txt_path"\]\s*=\s*run_file_url\(\s*rid\s*,\s*["\']reports/SUMMARY\.txt["\']\s*,\s*["\']reports/SHA256SUMS\.txt["\']\s*\)\s*$'
)
if pat.search(s):
    s = pat.sub(
        r'\g<ind>has["txt_path"] = run_file_url(rid, "reports/SUMMARY.txt")\n'
        r'\g<ind>has["sha_path"] = run_file_url(rid, "reports/SHA256SUMS.txt")',
        s
    )
    print("[OK] fixed run_file_url arg count + added sha_path")
else:
    # If not found, still try a looser match
    s2 = re.sub(
        r'has\["txt_path"\]\s*=\s*run_file_url\(\s*rid\s*,\s*["\']reports/SUMMARY\.txt["\']\s*,\s*["\']reports/SHA256SUMS\.txt["\']\s*\)',
        'has["txt_path"] = run_file_url(rid, "reports/SUMMARY.txt")\n    has["sha_path"] = run_file_url(rid, "reports/SHA256SUMS.txt")',
        s
    )
    if s2 != s:
        s = s2
        print("[OK] fixed run_file_url (loose) + added sha_path")

# (2) Extend allowlist literals: add reports/SHA256SUMS.txt wherever SUMMARY.txt is allowlisted
# Typical patterns: "reports/SUMMARY.txt" or 'reports/SUMMARY.txt'
if "reports/SHA256SUMS.txt" not in s:
    s = s.replace('"reports/SUMMARY.txt"', '"reports/SUMMARY.txt", "reports/SHA256SUMS.txt"')
    s = s.replace("'reports/SUMMARY.txt'", "'reports/SUMMARY.txt', 'reports/SHA256SUMS.txt'")
    # also bare filename allowlists
    s = s.replace('"SUMMARY.txt"', '"SUMMARY.txt", "SHA256SUMS.txt"')
    s = s.replace("'SUMMARY.txt'", "'SUMMARY.txt', 'SHA256SUMS.txt'")

# (3) Remove A2Z_INDEX from runs list if runs endpoint builds `items` then sorts.
# Insert filter right before items.sort(...) if present.
if "A2Z_INDEX" not in s:
    # Just ensure filter exists even without literal A2Z_INDEX elsewhere
    m = re.search(r'(?m)^\s*items\.sort\(.+\)\s*$', s)
    if m:
        ins = '\n    # '+MARK+' skip meta dirs\n    items = [x for x in items if (x.get("run_id")!="A2Z_INDEX")]\n'
        s = s[:m.start()] + ins + s[m.start():]

# If still no sort anchor, do nothing (safe)

if s == orig:
    raise SystemExit("[ERR] no change applied; cannot find target patterns.")

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] wrote:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

sudo systemctl restart vsp-ui-8910.service
sleep 1

BASE="http://127.0.0.1:8910"
echo "== smoke: /api/vsp/runs JSON =="
curl -sS -i "$BASE/api/vsp/runs?limit=5" | head -n 25

echo "== pick RID (first non-A2Z_INDEX) =="
RID="$(curl -sS "$BASE/api/vsp/runs?limit=50" | jq -r '.items[] | select(.run_id!="A2Z_INDEX") | .run_id' | head -n1)"
echo "RID=$RID"

echo "== smoke: sha256sums (must NOT be not allowed) =="
curl -sS -i "$BASE/api/vsp/run_file2?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 30 || true
