#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
cd "$ROOT"

echo "== find unify candidate =="
CAND="$(find "$ROOT" -maxdepth 3 -type f \( -name "unify.sh" -o -name "*unify*.sh" \) | grep -v "/ui/" | sort || true)"
echo "$CAND" | sed -n '1,40p'

if [ -z "$CAND" ]; then
  echo "[ERR] cannot find unify script under $ROOT (maxdepth=3)"
  echo "Hint: ls -la $ROOT/bin"
  ls -la "$ROOT/bin" 2>/dev/null || true
  exit 2
fi

TARGET=""
if [ -f "$ROOT/bin/unify.sh" ]; then
  TARGET="$ROOT/bin/unify.sh"
else
  TARGET="$(echo "$CAND" | head -n 1)"
fi
echo "[OK] patch target: $TARGET"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TARGET" "$TARGET.bak_merge_gitleaks_${TS}"
echo "[BACKUP] $TARGET.bak_merge_gitleaks_${TS}"

python3 - "$TARGET" <<'PY'
import sys, re
from pathlib import Path

target = Path(sys.argv[1])
t = target.read_text(encoding="utf-8", errors="ignore")
TAG = "# === VSP_UNIFY_MERGE_GITLEAKS_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

block = f"""
{TAG}
# Postprocess: ensure gitleaks findings appear in findings_unified.json (commercial Data Source)
# OUT_DIR is usually $1 in unify scripts.
if [ -n "${{1:-}}" ] && [ -d "${{1:-}}" ]; then
  /home/test/Data/SECURITY_BUNDLE/ui/bin/merge_gitleaks_into_findings_unified_v1.sh "${{1}}" >/dev/null 2>&1 || true
fi
"""

m = re.search(r"\n\s*exit\s+0\s*\n", t)
if m:
    t = t[:m.start()] + "\n" + block + "\n" + t[m.start():]
else:
    t = t.rstrip() + "\n" + block + "\n"

target.write_text(t, encoding="utf-8")
print("[OK] patched", str(target))
PY

echo "[DONE] next run unify will merge gitleaks into findings_unified automatically."
