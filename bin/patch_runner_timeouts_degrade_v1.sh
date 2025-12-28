#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
cd "$ROOT"

RUNNER="${1:-}"
if [ -z "${RUNNER}" ]; then
  if [ -f "bin/run_all_tools_v2.sh" ]; then
    RUNNER="bin/run_all_tools_v2.sh"
  else
    RUNNER="$(ls -1 bin/run_all_tools_v2* 2>/dev/null | head -n1 || true)"
  fi
fi

[ -n "${RUNNER}" ] || { echo "[ERR] cannot find runner"; exit 2; }
[ -f "${RUNNER}" ] || { echo "[ERR] missing runner: ${RUNNER}"; exit 2; }

if grep -q "VSP_TIMEOUT_RUN_V1" "${RUNNER}"; then
  echo "[OK] already patched: ${RUNNER}"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "${RUNNER}" "${RUNNER}.bak_timeouts_${TS}"
echo "[BACKUP] ${RUNNER}.bak_timeouts_${TS}"

python3 - <<PY
from pathlib import Path
import re

p = Path("${RUNNER}")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

helper = r'''
# ---- commercial hardening: timeout + degrade-graceful ----  # VSP_TIMEOUT_RUN_V1
: "${VSP_TIMEOUT_SEMGREP:=900}"
: "${VSP_TIMEOUT_TRIVY:=900}"
: "${VSP_TIMEOUT_KICS:=1200}"
: "${VSP_TIMEOUT_CODEQL:=1800}"

vsp_mark_degraded() {
  local tool="$1"; local reason="$2"; local rc="${3:-0}"
  echo "[VSP][DEGRADED] tool=${tool} reason=${reason} rc=${rc}"
  mkdir -p "$RUN_DIR/degraded"
  printf '%s\n' "${reason}" > "$RUN_DIR/degraded/${tool}.txt" || true
}

vsp_timeout_run() {
  local tool="$1"; local t="$2"; shift 2
  local start_ts; start_ts="$(date +%s)"
  echo "[VSP][TOOL][START] tool=${tool} timeout=${t}s"
  local rc=0
  if command -v timeout >/dev/null 2>&1; then
    timeout --preserve-status --signal=TERM "${t}" "$@" || rc=$?
  else
    "$@" || rc=$?
  fi
  local end_ts; end_ts="$(date +%s)"
  local dur=$((end_ts-start_ts))
  echo "[VSP][TOOL][END] tool=${tool} rc=${rc} dur_s=${dur}"

  # timeout-like
  if rc in (124,137,143) then
    :
  fi
}
'''

# python doesn't support bash "in", so render helper without that pseudo
helper = helper.replace("if rc in (124,137,143) then\n    :\n  fi\n", r'''if [ "${rc}" -eq 124 ] || [ "${rc}" -eq 137 ] || [ "${rc}" -eq 143 ]; then
    vsp_mark_degraded "${tool}" "timeout" "${rc}"
    return 0
  fi

  # missing tool
  if [ "${rc}" -eq 127 ]; then
    vsp_mark_degraded "${tool}" "missing_tool" "${rc}"
    return 0
  fi

  # keep pipeline alive even if tool fails (commercial: don't hang; unify/report still runs)
  return 0
}
''')

# insert helper after set -euo pipefail (or after shebang if not found)
ins_at = None
for i,l in enumerate(lines):
  if re.search(r'^\s*set\s+-euo\s+pipefail', l):
    ins_at = i+1
    break
if ins_at is None:
  ins_at = 1 if (lines and lines[0].startswith("#!")) else 0

out = lines[:ins_at] + [helper if helper.endswith("\n") else helper+"\n"] + lines[ins_at:]

text = "".join(out)

def wrap_first(pattern, tool, timeout_var):
  # Wrap the FIRST matching invocation line (common runners have single lane per tool)
  nonlocal_text = None

PY
