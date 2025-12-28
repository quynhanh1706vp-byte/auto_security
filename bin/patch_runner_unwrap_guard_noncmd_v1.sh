#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

F="bin/run_all_tools_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_unwrap_${TS}"
echo "[BACKUP] $F.bak_unwrap_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/run_all_tools_v2.sh")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

guard_re = re.compile(
    r'^(\s*)\$\{VSP_GUARD_TIMEOUT\}\s+"\$RUN_DIR"\s+"[A-Z]+"\s+"\$\{VSP_TMO_[A-Z]+\}"\s+--\s+(.*?)(\s*\|\|\s*true\s*)?$'
)

# prefixes that must NOT be wrapped
bad_prefixes = (
    "if ", "then", "fi", "elif ", "else", "for ", "while ", "do", "done",
    "case ", "esac",
    "{", "}", "(", ")",
    "export ", "unset ", "local ", "declare ", ": ",
    "[ ", "test ",
    "mkdir ", "cp ", "mv ", "rm ", "ln ", "touch ", "cat ", "echo ",
    "KICS_DIR=", "CODEQL_", "SEMGREP_", "TRIVY_", "OUT=", "SRC=", "ROOT=",
)

# patterns that ARE real tool executions (keep wrapped)
keep_markers = (
    " semgrep ", " semgrep\t", "semgrep scan",
    " trivy ", "trivy fs",
    " kics ", "kics scan",
    "run_kics_v2.sh", "run_kics", "checkmarx/kics",
    "codeql", "run_codeql", "run_codeql_sast",
    " timeout ", "timeout ",
    " bash ", "bash ",
)

out = []
changed = 0

for line in lines:
    m = guard_re.match(line.rstrip("\n"))
    if not m:
        out.append(line)
        continue

    indent, cmd, tail = m.group(1), m.group(2), (m.group(3) or "")
    cmd_stripped = cmd.lstrip()

    # if it's clearly a tool execution, keep wrapped
    if any(k in cmd for k in keep_markers):
        out.append(line)
        continue

    # if it starts with a non-executable/control-flow/util op, unwrap
    if cmd_stripped.startswith(bad_prefixes):
        new_line = indent + cmd + ((" " + tail.strip()) if tail.strip() else "")
        out.append(new_line + ("\n" if line.endswith("\n") else ""))
        changed += 1
        continue

    # default: keep wrapped (safer)
    out.append(line)

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] unwrapped_lines={changed}")
PY

bash -n "$F" && echo "[OK] bash -n OK"
echo "== [CHECK] any wrapped 'if' left? =="
grep -nE 'VSP_GUARD_TIMEOUT.*--\s*if\b' "$F" | head -n 50 || true
