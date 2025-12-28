#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/bin/run_semgrep_offline_local_clean_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

if grep -q "VSP_SEMGREP_EXCLUDES_V1" "$F"; then
  echo "[OK] already patched: $F"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_excludes_${TS}"
echo "[BACKUP] $F.bak_excludes_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("/home/test/Data/SECURITY_BUNDLE/bin/run_semgrep_offline_local_clean_v1.sh")
s=p.read_text(encoding="utf-8", errors="ignore")

# 1) Add excludes variable near top (after set -euo pipefail if exists)
inject = r'''
# ---- commercial excludes (noise) ----  # VSP_SEMGREP_EXCLUDES_V1
# NOTE: keep minimal to avoid dropping real findings; we only exclude generated/non-code.
VSP_SEMGREP_EXCLUDES=(
  "**/_ghcheck/**"
  "**/out_ci/**"
  "**/.git/**"
  "**/_codeql_db/**"
  "**/*.json"
)
# ---- end excludes ----
'''

if "VSP_SEMGREP_EXCLUDES_V1" not in s:
  m = re.search(r'^\s*set\s+-euo\s+pipefail\s*$', s, flags=re.M)
  if m:
    pos = m.end()
    s = s[:pos] + "\n" + inject + s[pos:]
  else:
    # fallback after shebang
    if s.startswith("#!"):
      nl = s.find("\n")
      s = s[:nl+1] + inject + s[nl+1:]
    else:
      s = inject + s

# 2) Patch semgrep invocation: add --exclude patterns before target dir
# Try to find a line that runs semgrep and has "$SRC_DIR" in it
lines = s.splitlines(True)
out=[]
patched=False
for line in lines:
  if (not patched) and ("semgrep" in line) and ("$SRC_DIR" in line) and ("--config" in line) and ("--exclude" not in line or "VSP_SEMGREP_EXCLUDES" not in line):
    # insert excludes before $SRC_DIR token
    # safe: append 'for ex in ...; do ARGS+=("..."); done' style is harder, so inline expansion:
    # add: $(printf ' --exclude %q' "${VSP_SEMGREP_EXCLUDES[@]}")  (bash)
    new = re.sub(r'(\s)(\$\{?SRC_DIR\}?|\$SRC_DIR|"\\$SRC_DIR"|"\$SRC_DIR")',
                 r' $(printf " --exclude %q" "${VSP_SEMGREP_EXCLUDES[@]}") \1\2',
                 line, count=1)
    if new != line:
      out.append(new)
      patched=True
      continue
  out.append(line)

if not patched:
  # If we can't safely patch invocation, at least we injected excludes variable; keep file valid
  pass

p.write_text("".join(out), encoding="utf-8")
print("[OK] semgrep clean patched (excludes injected, invocation best-effort patched=", patched, ")")
PY

bash -n "$F"
echo "[OK] bash -n OK"
echo "[DONE] patched $F"
