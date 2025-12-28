#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need date; need curl; need jq; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# auto-detect candidate file (best score)
CAND="$(
python3 - <<'PY'
from pathlib import Path
import re

hits=[]
for fp in Path(".").rglob("*.py"):
    try:
        s=fp.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    sc=0
    if "/api/vsp/run_file" in s: sc += 60
    if re.search(r"def\s+run_file\s*\(", s): sc += 40
    if "not allowed" in s: sc += 20
    if "request.args.get(\"rid\"" in s or "request.args.get('rid'" in s: sc += 10
    if "request.args.get(\"name\"" in s or "request.args.get('name'" in s: sc += 10
    if sc >= 60:
        hits.append((sc, str(fp)))
hits.sort(reverse=True)
print(hits[0][1] if hits else "")
PY
)"

if [ -z "${CAND:-}" ]; then
  echo "[ERR] cannot auto-detect run_file handler. Try:"
  echo "  grep -R --line-number '/api/vsp/run_file\\|def run_file' . | head -n 80"
  exit 3
fi

echo "[OK] detected handler file: $CAND"
cp -f "$CAND" "${CAND}.bak_allow_sha256sums_${TS}"
echo "[BACKUP] ${CAND}.bak_allow_sha256sums_${TS}"

export CAND

python3 - <<'PY'
from pathlib import Path
import os, re, time, sys

fp = Path(os.environ["CAND"])
s  = fp.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_ALLOW_SHA256SUMS_V5"
if MARK in s:
    print("[OK] already patched:", MARK)
    sys.exit(0)

sha_variants = [
    "reports/SHA256SUMS.txt",
    "reports/sha256sums.txt",
    "reports/SHA256SUMS",
    "reports/sha256sums",
]

orig = s
changed = False

# (A) Try: extend existing allowlist literal by adding SHA256SUMS next to SUMMARY/index
def add_to_allowlist_literal(text: str) -> str:
    nonlocal_changed = False

    # add after SUMMARY if present
    text2 = text.replace('"reports/SUMMARY.txt"', '"reports/SUMMARY.txt", "reports/SHA256SUMS.txt"')
    if text2 != text:
        nonlocal_changed = True
        text = text2

    text2 = text.replace("'reports/SUMMARY.txt'", "'reports/SUMMARY.txt', 'reports/SHA256SUMS.txt'")
    if text2 != text:
        nonlocal_changed = True
        text = text2

    # also bare filename lists
    text2 = text.replace('"SUMMARY.txt"', '"SUMMARY.txt", "SHA256SUMS.txt"')
    if text2 != text:
        nonlocal_changed = True
        text = text2

    text2 = text.replace("'SUMMARY.txt'", "'SUMMARY.txt', 'SHA256SUMS.txt'")
    if text2 != text:
        nonlocal_changed = True
        text = text2

    return text, nonlocal_changed

s2, ok = add_to_allowlist_literal(s)
if ok:
    s = s2
    changed = True

# (B) Fallback: inject bypass BEFORE the "not allowed" return inside run_file-like handler
if not changed:
    # find a block that returns err/not allowed and uses name or rel
    # pattern: if <cond>: return jsonify(...not allowed...)
    pat = re.compile(
        r"(?P<ifline>^\s*if\s+(?P<cond>.+?)\s*:\s*\n)"
        r"(?P<body>(?:^\s+.*\n){0,6}?)"
        r"^\s*return\s+jsonify\(\s*\{[^}]*not allowed[^}]*\}\s*\)\s*,\s*\d+\s*$",
        re.M
    )

    m = pat.search(s)
    if m:
        ifline = m.group("ifline")
        cond   = m.group("cond").strip()

        # We bypass allow if name/path is sha256sums
        # add helper above first occurrence of that if
        helper = "\n".join([
            "",
            f"# {MARK}",
            "def _vsp_allow_sha256sums(_p: str) -> bool:",
            "    try:",
            "        if not isinstance(_p, str):",
            "            return False",
            "        n = _p.replace('\\\\\\\\','/').lstrip('/')",
            "        if n.lower().startswith('reports/sha256sums'):",
            "            return True",
            "        return n in {",
        ] + [f"            '{x}'," for x in sha_variants] + [
            "        }",
            "    except Exception:",
            "        return False",
            "",
        ]) + "\n"

        # insert helper near top (after imports)
        lines = s.splitlines(True)
        ins = 0
        for i,l in enumerate(lines[:200]):
            if l.startswith("import ") or l.startswith("from "):
                ins = i+1
        lines.insert(ins, helper)
        s = "".join(lines)

        # now patch condition to allow sha256sums
        new_ifline = re.sub(r"^(\s*if\s+)(.+?)(\s*:\s*)$",
                            lambda mm: mm.group(1) + f"(({mm.group(2)}) and (not _vsp_allow_sha256sums(name if 'name' in locals() else rel if 'rel' in locals() else path if 'path' in locals() else ''))" + mm.group(3),
                            ifline.strip(), flags=re.M)
        # ensure it kept newline
        new_ifline = new_ifline + "\n"

        # replace the original if line only once
        s = s.replace(ifline, new_ifline, 1)
        changed = True

# (C) Last resort: if still not changed, hard fail with hint
if not changed:
    print("[ERR] could not patch allowlist/bypass automatically in", fp)
    print("HINT: open the file and search for 'not allowed' or '/api/vsp/run_file' and show that block.")
    sys.exit(4)

# write + mark
bak = fp.with_suffix(fp.suffix + f".bak_v5_{int(time.time())}")
bak.write_text(orig, encoding="utf-8")
fp.write_text(s + f"\n# {MARK}\n", encoding="utf-8")
print("[OK] patched:", fp)
print("[BACKUP2]", bak)
PY

python3 -m py_compile "$CAND"
echo "[OK] py_compile OK: $CAND"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"

BASE="http://127.0.0.1:8910"
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"

echo "== smoke GET (must NOT be not-allowed) =="
curl -sS -i "$BASE/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 30
