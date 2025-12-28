#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need date; need find; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) auto-detect python file that implements /api/vsp/run_file or run_file handler
CAND="$(
  python3 - <<'PY'
from pathlib import Path
import re, sys

root = Path(".")
hits = []

for fp in root.rglob("*.py"):
    try:
        s = fp.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue

    # strongest signals
    score = 0
    if "/api/vsp/run_file" in s: score += 50
    if re.search(r"def\s+run_file\s*\(", s): score += 50
    if "run_file" in s: score += 5
    if "request.args.get('rid'" in s or 'request.args.get("rid"' in s: score += 3
    if "request.args.get('name'" in s or 'request.args.get("name"' in s: score += 3
    if score >= 55:
        hits.append((score, str(fp)))

hits.sort(reverse=True)
print(hits[0][1] if hits else "")
PY
)"

if [ -z "${CAND:-}" ]; then
  echo "[ERR] cannot auto-detect run_file handler. Run:"
  echo "  grep -R --line-number \"def run_file\\b\\|/api/vsp/run_file\" . | head -n 80"
  exit 3
fi

echo "[OK] detected handler file: $CAND"

# 2) backup
cp -f "$CAND" "${CAND}.bak_allow_sha256sums_${TS}"
echo "[BACKUP] ${CAND}.bak_allow_sha256sums_${TS}"

# 3) patch
python3 - <<'PY'
from pathlib import Path
import re

fp = Path("'"$CAND"'")
s  = fp.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_ALLOW_SHA256SUMS_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# We try to patch allowlist block if it exists, otherwise inject a pre-allow clause before any 403/abort logic.

sha_names = [
    "reports/sha256sums.txt",
    "reports/sha256sums.json",
    "reports/SHA256SUMS",
    "reports/SHA256SUMS.txt",
    "reports/sha256sums",
]

def add_into_literal_block(text: str) -> str|None:
    # Find a set/list that already contains reports/index.html and add sha entries into it.
    # Handles patterns like: allowed = { "reports/index.html", ... } or [ ... ]
    m = re.search(r"(reports/index\.html)", text)
    if not m:
        return None

    # find nearest bracketed literal containing that token (simple heuristic)
    i = m.start()
    left = text.rfind("{", 0, i)
    right = text.find("}", i)
    kind = "set"
    if left == -1 or right == -1 or right - left > 3000:
        left = text.rfind("[", 0, i)
        right = text.find("]", i)
        kind = "list"
    if left == -1 or right == -1 or right - left > 3000:
        return None

    block = text[left:right+1]
    for name in sha_names:
        if name in block:
            continue
        # insert before closing brace/bracket with nice indent
        insert = f'    "{name}",\n'
        block = block[:-1] + insert + block[-1:]
    return text[:left] + block + text[right+1:]

patched = add_into_literal_block(s)
if patched is None:
    # Fallback: inject guard inside run_file handler right after reading 'name'
    # Locate name = request.args.get('name'...) line
    m = re.search(r"^\s*name\s*=\s*request\.args\.get\(\s*['\"]name['\"].*$", s, flags=re.M)
    if not m:
        # as a last resort, inject near top with no-op (won't help), so we hard fail instead
        raise SystemExit("[ERR] cannot locate name=request.args.get('name') in handler; abort patch")

    inj = "\n".join([
        "",
        f"    # {MARK}",
        "    # allow sha256sums artifacts in reports/ (commercial export support)",
        "    if isinstance(name, str):",
        "        _n = name.replace('\\\\\\\\','/').lstrip('/')",
        "        if _n.startswith('reports/sha256sums') or _n in {",
    ] + [f"            '{x}'," for x in sha_names] + [
        "        }:",
        "            name = _n",
        "",
    ]) + "\n"

    s2 = s[:m.end()] + inj + s[m.end():]
    fp.write_text(s2, encoding="utf-8")
    print("[OK] injected allow-guard (fallback) in run_file:", MARK)
else:
    fp.write_text(patched + f"\n# {MARK}\n", encoding="utf-8")
    print("[OK] patched allowlist literal:", MARK)
PY

# 4) compile + restart
python3 -m py_compile "$CAND"
echo "[OK] py_compile OK: $CAND"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"

echo "== SMOKE (expect 200 or 404; must NOT be 403) =="
RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs?limit=1' | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("items") or [{}])[0].get("run_id",""))' 2>/dev/null || true)"
echo "[RID]=$RID"
if [ -n "${RID:-}" ]; then
  curl -sS -o /dev/null -D - "http://127.0.0.1:8910/api/vsp/run_file?rid=${RID}&name=reports%2Fsha256sums.txt" | head -n 15
fi
