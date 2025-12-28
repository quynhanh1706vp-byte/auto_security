#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_finalize_bash_${TS}"
echo "[BACKUP] $PYF.bak_finalize_bash_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Replace subprocess.run([str(script), arg]) with subprocess.run(["bash", str(script), arg])
txt2 = txt

# unify call
txt2 = re.sub(
    r"subprocess\.run\(\[\s*str\(unify\)\s*,\s*str\(st\[\s*['\"]ci_run_dir['\"]\s*\]\)\s*\]",
    r"subprocess.run(['bash', str(unify), str(st['ci_run_dir'])]",
    txt2
)

# sync call (var name may be syncsh)
txt2 = re.sub(
    r"subprocess\.run\(\[\s*str\(syncsh\)\s*,\s*str\(st\[\s*['\"]ci_run_dir['\"]\s*\]\)\s*\]",
    r"subprocess.run(['bash', str(syncsh), str(st['ci_run_dir'])]",
    txt2
)

# also handle direct /bin/vsp_ci_sync_to_vsp_v1.sh usage if present
txt2 = txt2.replace("subprocess.run([str(sync), str(ci_run_dir)]", "subprocess.run(['bash', str(sync), str(ci_run_dir)]")

if txt2 == txt:
    print("[WARN] no finalize subprocess.run patterns replaced (file may differ).")
else:
    p.write_text(txt2, encoding="utf-8")
    print("[OK] patched finalize calls to use bash")
PY

python3 -m py_compile "$PYF"
echo "[OK] py_compile OK"
