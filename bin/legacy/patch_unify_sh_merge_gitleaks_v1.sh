#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

F="bin/unify.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_merge_gitleaks_${TS}"
echo "[BACKUP] $F.bak_merge_gitleaks_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/unify.sh")
t=p.read_text(encoding="utf-8", errors="ignore")
TAG="# === VSP_UNIFY_MERGE_GITLEAKS_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

block = f"""
{TAG}
# Postprocess: ensure gitleaks findings appear in findings_unified.json (commercial Data Source)
if [ -n "${{1:-}}" ] && [ -d "${{1:-}}" ]; then
  /home/test/Data/SECURITY_BUNDLE/ui/bin/merge_gitleaks_into_findings_unified_v1.sh "${{1}}" >/dev/null 2>&1 || true
fi
"""

# insert near end (before last exit if any), else append
m=re.search(r"\n\s*exit\s+0\s*\n", t)
if m:
    t = t[:m.start()] + "\n" + block + "\n" + t[m.start():]
else:
    t = t.rstrip() + "\n" + block + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] patched unify.sh")
PY

echo "[DONE] unify.sh will merge gitleaks into findings_unified automatically."
