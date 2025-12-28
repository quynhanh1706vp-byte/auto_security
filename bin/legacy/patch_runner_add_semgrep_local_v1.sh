#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
cd "$ROOT"

# pick runner (allow override)
RUNNER="${1:-}"
if [ -z "${RUNNER}" ]; then
  if [ -f "bin/run_all_tools_v2.sh" ]; then
    RUNNER="bin/run_all_tools_v2.sh"
  else
    RUNNER="$(ls -1 bin/run_all_tools_v2* 2>/dev/null | head -n1 || true)"
  fi
fi

[ -n "${RUNNER}" ] || { echo "[ERR] cannot find runner under $ROOT/bin"; exit 2; }
[ -f "${RUNNER}" ] || { echo "[ERR] missing runner: ${RUNNER}"; exit 2; }

if grep -q "SEMGREP_LOCAL_OFFLINE_V1" "${RUNNER}"; then
  echo "[OK] already patched: ${RUNNER}"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "${RUNNER}" "${RUNNER}.bak_semgrep_local_${TS}"
echo "[BACKUP] ${RUNNER}.bak_semgrep_local_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

runner = Path(re.sub(r"\s+$","",open("/proc/self/cmdline","rb").read().decode("utf-8","ignore")))
PY 2>/dev/null || true

python3 - <<PY
from pathlib import Path
import re

p = Path("${RUNNER}")
s = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

insert_block = r'''
# ===== [SEMGREP_LOCAL] =====  # SEMGREP_LOCAL_OFFLINE_V1
echo "===== [SEMGREP_LOCAL] semgrep offline-local (root-only configs) ====="
if [ -s "$RUN_DIR/semgrep/semgrep.json" ]; then
  echo "[SEMGREP_LOCAL] found existing \$RUN_DIR/semgrep/semgrep.json => skip"
else
  /home/test/Data/SECURITY_BUNDLE/bin/run_semgrep_offline_local_clean_v1.sh "$RUN_DIR" "$SRC_DIR" || true
fi
'''

# Try to insert BEFORE unify stage/call; fallback: before script end
pat_candidates = [
  re.compile(r'^\s*echo\s+["\']=====.*\bUNIFY\b', re.I),
  re.compile(r'^\s*#\s*=====.*\bUNIFY\b', re.I),
  re.compile(r'\bvsp_unify\b|\bunify_findings\b|\bvsp_unify_findings\b', re.I),
]
idx = None
for i,line in enumerate(s):
  if any(pat.search(line) for pat in pat_candidates):
    idx = i
    break

# If runner already has a Semgrep stage, prefer inserting right BEFORE that stage to keep tool order
semgrep_pat = re.compile(r'\bSEMGREP\b|\brun_semgrep\b|\bsemgrep\b', re.I)
semgrep_idx = None
for i,line in enumerate(s):
  # avoid matching comments that mention semgrep in docs only
  if semgrep_pat.search(line) and ("echo" in line or "run_" in line or "/semgrep" in line):
    semgrep_idx = i
    break

if semgrep_idx is not None:
  idx = semgrep_idx

if idx is None:
  idx = len(s)

# Insert
out = s[:idx] + [insert_block if insert_block.endswith("\n") else insert_block+"\n"] + s[idx:]
p.write_text("".join(out), encoding="utf-8")
print(f"[OK] inserted SEMGREP_LOCAL block at line~{idx+1} in {p}")
PY

python3 -m py_compile "${RUNNER}"
echo "[OK] py_compile OK"
echo "[DONE] patched ${RUNNER}"
