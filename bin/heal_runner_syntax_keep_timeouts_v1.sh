#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

F="bin/run_all_tools_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [CHECK] current bash -n =="
if bash -n "$F" 2>/dev/null; then
  echo "[OK] current runner syntax OK"
else
  echo "[WARN] current runner syntax FAIL; trying to auto-restore a good backup..."
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$F" "$F.broken_${TS}"
  echo "[BACKUP] $F.broken_${TS}"

  good=""
  # newest first
  for b in $(ls -1t bin/run_all_tools_v2.sh.bak_* 2>/dev/null || true); do
    if bash -n "$b" 2>/dev/null; then
      good="$b"; break
    fi
  done

  if [ -z "$good" ]; then
    echo "[ERR] no backup with valid syntax found"; exit 2
  fi

  cp -f "$good" "$F"
  echo "[RESTORE] $good -> $F"
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_repatch_${TS}"
echo "[BACKUP] $F.bak_repatch_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/run_all_tools_v2.sh")
s=p.read_text(encoding="utf-8", errors="ignore")

# ensure guard + timeout vars exist
if "VSP_TIMEOUTS_4TOOLS_V1" not in s:
    block = r'''
# === VSP_TIMEOUTS_4TOOLS_V1 (commercial: CI never hang) ===
: "${VSP_TMO_SEMGREP:=1200}"  # 20m
: "${VSP_TMO_TRIVY:=1500}"    # 25m
: "${VSP_TMO_KICS:=1800}"     # 30m
: "${VSP_TMO_CODEQL:=3600}"   # 60m
VSP_GUARD_TIMEOUT="${VSP_GUARD_TIMEOUT:-/home/test/Data/SECURITY_BUNDLE/bin/vsp_timeout_guard_v1.sh}"
# === /VSP_TIMEOUTS_4TOOLS_V1 ===
'''
    m=re.search(r"set\s+-euo\s+pipefail\s*\n", s)
    if m: s = s[:m.end()] + block + s[m.end():]
    else: s = block + "\n" + s

# wrap only REAL tool commands (no if/fi/assign/mkdir/cp/rm)
def wrap_line(line, tool, tmo):
    if "VSP_GUARD_TIMEOUT" in line: 
        return line
    if re.match(r"^\s*(#|if\b|then\b|fi\b|elif\b|else\b|for\b|while\b|do\b|done\b|case\b|esac\b)", line):
        return line
    if re.match(r"^\s*[A-Za-z_][A-Za-z0-9_]*=", line):
        return line
    if re.match(r"^\s*(mkdir|cp|mv|rm|ln|touch|cat|echo)\b", line):
        return line
    indent=re.match(r"^\s*", line).group(0)
    tail=""
    if "|| true" in line:
        head, tail = line.split("|| true", 1)
        tail="|| true"+tail
        cmd=head.strip()
    else:
        cmd=line.strip()
    nl="\n" if line.endswith("\n") else ""
    return f'{indent}${{VSP_GUARD_TIMEOUT}} "$RUN_DIR" "{tool}" "${{{tmo}}}" -- {cmd} {tail}'.rstrip()+nl

lines=s.splitlines(True)
out=[]
chg=0
for line in lines:
    nl=line
    # KICS commercial runner
    if "run_kics_v2.sh" in line and "bash" not in line:
        nl = wrap_line(line, "KICS", "VSP_TMO_KICS")
    # CODEQL runner script
    elif "run_codeql_sast_v2.sh" in line:
        nl = wrap_line(line, "CODEQL", "VSP_TMO_CODEQL")
    # semgrep cli
    elif "semgrep scan" in line and "--json" in line:
        nl = wrap_line(line, "SEMGREP", "VSP_TMO_SEMGREP")
    # trivy fs
    elif "trivy fs" in line and "--format json" in line:
        nl = wrap_line(line, "TRIVY", "VSP_TMO_TRIVY")

    if nl != line: chg += 1
    out.append(nl)

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] repatched_wrapped_lines={chg}")
PY

bash -n "$F" && echo "[OK] final bash -n OK"
echo "== [CHECK] no wrapped if =="
grep -nE 'VSP_GUARD_TIMEOUT.*--\s*if\b' "$F" | head -n 20 || true
