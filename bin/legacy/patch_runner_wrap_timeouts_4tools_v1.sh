#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

F="bin/run_all_tools_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

GUARD="/home/test/Data/SECURITY_BUNDLE/bin/vsp_timeout_guard_v1.sh"
[ -x "$GUARD" ] || { echo "[ERR] missing or not executable: $GUARD"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_timeouts4_${TS}"
echo "[BACKUP] $F.bak_timeouts4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/run_all_tools_v2.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

# 1) ensure defaults (idempotent)
if "VSP_TIMEOUTS_4TOOLS_V1" not in s:
    insert = r'''
# === VSP_TIMEOUTS_4TOOLS_V1 (commercial: CI never hang) ===
: "${VSP_TMO_SEMGREP:=1200}"  # 20m
: "${VSP_TMO_TRIVY:=1500}"    # 25m
: "${VSP_TMO_KICS:=1800}"     # 30m
: "${VSP_TMO_CODEQL:=3600}"   # 60m
VSP_GUARD_TIMEOUT="${VSP_GUARD_TIMEOUT:-/home/test/Data/SECURITY_BUNDLE/bin/vsp_timeout_guard_v1.sh}"
# === /VSP_TIMEOUTS_4TOOLS_V1 ===
'''
    # insert after set -euo pipefail if possible
    m = re.search(r"set\s+-euo\s+pipefail\s*\n", s)
    if m:
        s = s[:m.end()] + insert + s[m.end():]
    else:
        s = insert + "\n" + s

# 2) wrap calls by script-name patterns (line-based, safe)
tool_map = [
    ("SEMGREP", "VSP_TMO_SEMGREP", [
        "run_semgrep_offline_local_clean_v1.sh",
        "run_semgrep",
        "/semgrep",
    ]),
    ("TRIVY", "VSP_TMO_TRIVY", [
        "run_trivy",
        "trivy_fs",
        "/trivy",
    ]),
    ("KICS", "VSP_TMO_KICS", [
        "run_kics",
        "checkmarx/kics",
        "/kics",
    ]),
    ("CODEQL", "VSP_TMO_CODEQL", [
        "run_codeql",
        "/codeql",
    ]),
]

lines = s.splitlines(True)
out = []
changed = 0

def should_wrap(line: str, needles: list[str]) -> bool:
    if "vsp_timeout_guard_v1.sh" in line or "VSP_GUARD_TIMEOUT" in line:
        return False
    if line.lstrip().startswith("#"):
        return False
    # avoid wrapping echoes/labels
    if re.search(r'^\s*echo\b', line):
        return False
    return any(n in line for n in needles)

for line in lines:
    new_line = line
    for tool, tmo_var, needles in tool_map:
        if should_wrap(line, needles):
            # split optional "|| true" tail (preserve)
            tail = ""
            if "|| true" in line:
                head, tail = line.split("|| true", 1)
                tail = "|| true" + tail
            else:
                head = line

            indent = re.match(r"^\s*", head).group(0)
            cmd = head.strip()
            # if empty after strip, skip
            if not cmd:
                break

            new_line = (
                f'{indent}${{VSP_GUARD_TIMEOUT}} "$RUN_DIR" "{tool}" "${{{tmo_var}}}" -- {cmd} {tail}'.rstrip()
                + ("\n" if line.endswith("\n") else "")
            )
            changed += 1
            break
    out.append(new_line)

s2 = "".join(out)
p.write_text(s2, encoding="utf-8")
print(f"[OK] wrapped_lines={changed}")
PY

bash -n "$F" && echo "[OK] bash -n OK"
echo "== [CHECK] wrapped occurrences =="
grep -nE "VSP_GUARD_TIMEOUT|vsp_timeout_guard_v1\.sh|VSP_TIMEOUTS_4TOOLS_V1" "$F" | head -n 80
