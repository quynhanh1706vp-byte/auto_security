#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

F="bin/run_all_tools_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_tmo8_${TS}"
echo "[BACKUP] $F.bak_tmo8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/run_all_tools_v2.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

# 1) ensure timeout vars for remaining 4 tools (idempotent)
if "VSP_TIMEOUTS_8TOOLS_V1" not in s:
    block = r'''
# === VSP_TIMEOUTS_8TOOLS_V1 (commercial: CI never hang, extend) ===
: "${VSP_TMO_BANDIT:=900}"    # 15m
: "${VSP_TMO_GITLEAKS:=900}"  # 15m
: "${VSP_TMO_SYFT:=1200}"     # 20m
: "${VSP_TMO_GRYPE:=1200}"    # 20m
# === /VSP_TIMEOUTS_8TOOLS_V1 ===
'''
    # insert right after existing VSP_TIMEOUTS_4TOOLS_V1 if present, else after set -euo pipefail
    m = re.search(r"# === /VSP_TIMEOUTS_4TOOLS_V1 ===\s*\n", s)
    if m:
        s = s[:m.end()] + block + s[m.end():]
    else:
        m2 = re.search(r"set\s+-euo\s+pipefail\s*\n", s)
        if m2:
            s = s[:m2.end()] + block + s[m2.end():]
        else:
            s = block + "\n" + s

# 2) wrap ONLY real executable lines that call these tools/scripts (avoid if/assign/mkdir/cp)
lines = s.splitlines(True)
out = []
changed = 0

guard_prefix_re = re.compile(r'^\s*\$\{VSP_GUARD_TIMEOUT\}\s+"\$RUN_DIR"\s+"[A-Z]+"\s+"\$\{VSP_TMO_[A-Z]+\}"\s+--\s+')
comment_re = re.compile(r'^\s*#')
keyword_or_assign_re = re.compile(r'^\s*(if|then|fi|elif|else|for|while|do|done|case|esac)\b|^\s*[A-Za-z_][A-Za-z0-9_]*=')

def wrap(line: str, tool: str, tmo: str) -> str:
    # preserve trailing "|| true"
    tail = ""
    if "|| true" in line:
        head, tail = line.split("|| true", 1)
        tail = "|| true" + tail
    else:
        head = line
    indent = re.match(r"^\s*", head).group(0)
    cmd = head.strip()
    nl = "\n" if line.endswith("\n") else ""
    return f'{indent}${{VSP_GUARD_TIMEOUT}} "$RUN_DIR" "{tool}" "${{{tmo}}}" -- {cmd} {tail}'.rstrip() + nl

targets = [
    ("BANDIT", "VSP_TMO_BANDIT", [
        "run_bandit", "bandit ", "/bandit", "bandit.json"
    ]),
    ("GITLEAKS", "VSP_TMO_GITLEAKS", [
        "run_gitleaks", "gitleaks ", "/gitleaks", "gitleaks.json"
    ]),
    ("SYFT", "VSP_TMO_SYFT", [
        "run_syft", "syft ", "/syft", "syft.json"
    ]),
    ("GRYPE", "VSP_TMO_GRYPE", [
        "run_grype", "grype ", "/grype", "grype.json"
    ]),
]

for line in lines:
    if guard_prefix_re.search(line) or comment_re.match(line) or keyword_or_assign_re.match(line):
        out.append(line); continue

    new_line = line
    for tool, tmo, needles in targets:
        if any(n in line for n in needles):
            # avoid wrapping echoes
            if re.match(r'^\s*echo\b', line): 
                break
            new_line = wrap(line, tool, tmo)
            changed += 1
            break
    out.append(new_line)

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] wrapped_lines={changed}")
PY

bash -n "$F" && echo "[OK] bash -n OK"
echo "== [CHECK] tool wrappers present =="
grep -nE 'VSP_TMO_(BANDIT|GITLEAKS|SYFT|GRYPE)|"\s*(BANDIT|GITLEAKS|SYFT|GRYPE)\s*"\s+"\$\{VSP_TMO_' "$F" | head -n 120
