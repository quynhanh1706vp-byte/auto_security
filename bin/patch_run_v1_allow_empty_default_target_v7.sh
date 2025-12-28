#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

ERRSTR="target_type=path and target required"

echo "== [1] find python files that return the strict 400 =="
python3 - <<'PY'
from pathlib import Path
import sys

root = Path(".")
hits = []
for f in root.rglob("*.py"):
    try:
        txt = f.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    if "target_type=path and target required" in txt:
        hits.append(str(f))
print("\n".join(hits))
if not hits:
    sys.exit(2)
PY

FILES="$(python3 - <<'PY'
from pathlib import Path
hits=[]
for f in Path(".").rglob("*.py"):
    try:
        txt=f.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    if "target_type=path and target required" in txt:
        hits.append(str(f))
print(" ".join(hits))
PY
)"

if [ -z "${FILES:-}" ]; then
  echo "[ERR] cannot find any .py containing: $ERRSTR"
  exit 1
fi

echo "[FOUND] $FILES"

echo "== [2] patch each file (backup + replace strict block with default) =="
TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<PY
from pathlib import Path
import re, sys

files = """$FILES""".split()
DEFAULT_TARGET = "/home/test/Data/SECURITY-10-10-v4"
TAG = "# === VSP_RUN_V1_ALLOW_EMPTY_DEFAULT_TARGET_V7 ==="

patched_any = False

for fp in files:
    p = Path(fp)
    t = p.read_text(encoding="utf-8", errors="ignore")

    # backup
    b = p.with_suffix(p.suffix + f".bak_allow_empty_v7_$TS")
    b.write_text(t, encoding="utf-8")
    print("[BACKUP]", b)

    lines = t.splitlines(True)
    # locate the return line that contains the error string
    idxs = [i for i,l in enumerate(lines) if "target_type=path and target required" in l]
    if not idxs:
        continue

    for i in idxs:
        # search upward for a nearby if-block line
        j = i
        while j >= 0 and (i - j) <= 30:
            if re.match(r"^\s*if\s+.*target_type.*path.*not.*target", lines[j]):
                break
            j -= 1
        if j < 0 or (i - j) > 30:
            continue

        indent = re.match(r"^(\s*)", lines[j]).group(1)

        # find end of block (at least include the return line i)
        k = i
        # include subsequent lines if return spans multiple lines (jsonify(...) broken lines)
        while k + 1 < len(lines) and lines[k+1].lstrip().startswith((")", "}","],", "})", "),", ",")):
            k += 1

        # replace block j..k
        repl = []
        repl.append(f"{indent}{TAG}\n")
        repl.append(f"{indent}if target_type == 'path' and (not target):\n")
        repl.append(f"{indent}    # commercial: accept empty payload by applying default target\n")
        repl.append(f"{indent}    target = '{DEFAULT_TARGET}'\n")
        repl.append(f"{indent}    try:\n")
        repl.append(f"{indent}        if isinstance(j, dict):\n")
        repl.append(f"{indent}            j['target'] = target\n")
        repl.append(f"{indent}            j.setdefault('target_type','path')\n")
        repl.append(f"{indent}            j.setdefault('mode','local')\n")
        repl.append(f"{indent}            j.setdefault('profile','FULL_EXT')\n")
        repl.append(f"{indent}    except Exception:\n")
        repl.append(f"{indent}        pass\n")
        repl.append(f"{indent}    # NOTE: do not return 400 here; continue run spawn\n")

        lines[j:k+1] = repl
        patched_any = True
        print(f"[OK] patched block in {fp} (lines {j+1}-{k+1})")
        break

    p.write_text("".join(lines), encoding="utf-8")

if not patched_any:
    print("[ERR] found error string but failed to patch any if/return block automatically")
    sys.exit(3)

print("[OK] done")
PY

echo "== [3] compile + restart service =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== [4] verify POST {} to /api/vsp/run_v1 (should be 200 now) =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d '{}' | sed -n '1,180p'
