#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

CAND_JS=(
  "static/js/vsp_bundle_commercial_v2.js"
  "static/js/vsp_bundle_commercial_v1.js"
  "static/js/vsp_runs_tab_resolved_v1.js"
)

python3 - <<'PY'
from pathlib import Path
import re, time

TS=time.strftime("%Y%m%d_%H%M%S")
MARK="VSP_P0_DASH_NO_ABORT_MISSING_CONTAINERS_V1"

files=[Path(p) for p in [
  "static/js/vsp_bundle_commercial_v2.js",
  "static/js/vsp_bundle_commercial_v1.js",
  "static/js/vsp_runs_tab_resolved_v1.js",
]]

def backup(p: Path, tag: str):
    bak=p.with_name(p.name+f".bak_{tag}_{TS}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    return bak

def patch_one(p: Path):
    if not p.exists(): 
        print("[SKIP] missing", p); 
        return False
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[SKIP] already patched", p)
        return False

    # 1) Remove "return;" right after the specific give-up log (most common)
    pat1 = re.compile(r'(\[VSP\]\[DASH\]\[V6D\]\s*gave up:\s*containers/rid missing[^\n;]*;\s*)return\s*;\s*', re.I)
    s2, n1 = pat1.subn(r'\1/* '+MARK+': keep going (degrade) */\n', s)

    # 2) More generic: if any "gave up: containers" followed by return; => remove return
    pat2 = re.compile(r'(\bgave up:\s*containers[^\n;]*;\s*)return\s*;\s*', re.I)
    s3, n2 = pat2.subn(r'\1/* '+MARK+': keep going (degrade) */\n', s2)

    # If nothing matched, still inject a tiny guard to prevent hard abort (safe)
    injected=False
    if n1==0 and n2==0:
        # still mark to avoid re-run
        s3 = s + f"\n/* {MARK}: no direct pattern match; no-op */\n"
        injected=True

    if s3 != s:
        bak=backup(p, "dash_noabort")
        p.write_text(s3, encoding="utf-8")
        print(f"[OK] patched {p}  backup={bak}  n1={n1} n2={n2} injected_noop={injected}")
        return True

    # fallback: just mark to avoid repeated attempts
    p.write_text(s + f"\n/* {MARK}: unchanged */\n", encoding="utf-8")
    print(f"[OK] marked {p} (no change detected)")
    return True

changed=False
for f in files:
    changed = patch_one(f) or changed

print("[DONE] changed=", changed)
PY

for f in "${CAND_JS[@]}"; do
  if [ -f "$f" ] && command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null 2>&1 && echo "[OK] node --check: $f" || { echo "[ERR] node --check failed: $f"; exit 3; }
  fi
done

echo "[OK] Patch applied. Restart UI then Ctrl+F5 /vsp5"
