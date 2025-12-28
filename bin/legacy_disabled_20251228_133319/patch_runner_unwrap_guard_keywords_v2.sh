#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

F="bin/run_all_tools_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_unwrapkw_${TS}"
echo "[BACKUP] $F.bak_unwrapkw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/run_all_tools_v2.sh")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# match our wrapped line format
guard_re = re.compile(
    r'^(\s*)\$\{VSP_GUARD_TIMEOUT\}\s+"\$RUN_DIR"\s+"[A-Z]+"\s+"\$\{VSP_TMO_[A-Z]+\}"\s+--\s+(.*?)(\s*\|\|\s*true\s*)?$'
)

# Things that must NEVER be wrapped (keywords / assignments / file ops)
kw_prefix = re.compile(r'^(if|then|fi|elif|else|for|while|do|done|case|esac)\b')
assign_prefix = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=')
fsop_prefix = re.compile(r'^(mkdir|cp|mv|rm|ln|touch|cat|echo)\b')
test_prefix = re.compile(r'^(\[|test)\b')
brace_prefix = re.compile(r'^(\{|\}|\(|\))\s*$')

out = []
changed = 0

for line in lines:
    m = guard_re.match(line.rstrip("\n"))
    if not m:
        out.append(line)
        continue

    indent, cmd, tail = m.group(1), m.group(2), (m.group(3) or "")
    cmd_stripped = cmd.lstrip()

    must_unwrap = (
        kw_prefix.match(cmd_stripped) or
        assign_prefix.match(cmd_stripped) or
        fsop_prefix.match(cmd_stripped) or
        test_prefix.match(cmd_stripped) or
        brace_prefix.match(cmd_stripped) or
        cmd_stripped.startswith(": ") or
        cmd_stripped.startswith("export ") or
        cmd_stripped.startswith("unset ") or
        cmd_stripped.startswith("local ") or
        cmd_stripped.startswith("declare ")
    )

    if must_unwrap:
        # restore original command line (keep "|| true" tail if existed)
        new_line = indent + cmd
        if tail.strip():
            new_line += " " + tail.strip()
        out.append(new_line + ("\n" if line.endswith("\n") else ""))
        changed += 1
    else:
        out.append(line)

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] unwrapped_lines={changed}")
PY

# hard gate: syntax must pass
bash -n "$F" && echo "[OK] bash -n OK"

echo "== [CHECK] wrapped 'if' left? (should be empty) =="
grep -nE 'VSP_GUARD_TIMEOUT.*--\s*if\b' "$F" | head -n 50 || true
echo "== [CHECK] wrapped assignments left? (should be empty) =="
grep -nE 'VSP_GUARD_TIMEOUT.*--\s*[A-Za-z_][A-Za-z0-9_]*=' "$F" | head -n 50 || true
