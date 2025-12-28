#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] scanning static/js for injected guard..."

python3 - <<'PY'
from pathlib import Path
import re, time

root = Path("static/js")
files = []
for p in root.glob("*.js"):
    try:
        t = p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    if "[VSP_COMMERCIAL_GUARD]" in t and "Illegal return" not in t:
        files.append(p)

# Also include the known ones if exist
for name in [
    "vsp_degraded_panel_hook_v3.js",
    "vsp_tool_pills_verdict_from_gate_p0_v1.js",
    "vsp_tool_pills_verdict_from_gate_p0_v2.js",
    "vsp_tools_status_from_gate_p0_v1.js",
]:
    p = root / name
    if p.exists() and p not in files:
        t = p.read_text(encoding="utf-8", errors="ignore")
        if "[VSP_COMMERCIAL_GUARD]" in t:
            files.append(p)

pat = re.compile(
    r"\n\s*function __vsp_is_runs\(\)\s*\{[\s\S]*?\}\s*"
    r"\n\s*function __vsp_policy_open\(\)\s*\{[\s\S]*?\}\s*"
    r"\n\s*// If not on runs[\s\S]*?\n\s*if\s*\(\s*!\s*__vsp_is_runs\(\)\s*&&\s*!\s*__vsp_policy_open\(\)\s*\)\s*\{[\s\S]*?\n\s*return;\s*\n\s*\}\s*\n",
    re.M
)

patched = 0
ts = time.strftime("%Y%m%d_%H%M%S")
for p in files:
    s = p.read_text(encoding="utf-8", errors="ignore")
    if "[VSP_COMMERCIAL_GUARD]" not in s:
        continue
    s2, n = pat.subn("\n", s, count=1)
    if n == 0:
        # fallback: remove just the return-guard block (looser)
        s2 = re.sub(r"\n[\s\S]*?\[VSP_COMMERCIAL_GUARD\][\s\S]*?return;\s*\n\s*\}\s*\n", "\n", s, count=1)
        if s2 == s:
            continue
    bak = p.with_suffix(p.suffix + f".bak_unguard_{ts}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(s2, encoding="utf-8")
    print("[OK] unguarded", p.name, "backup=>", bak.name)
    patched += 1

print("[DONE] unguard patched files =", patched)
PY

# syntax check best-effort
for f in static/js/*.js; do
  if grep -q "\[VSP_COMMERCIAL_GUARD\]" "$f" 2>/dev/null; then
    echo "[WARN] still has guard marker: $f"
  fi
done

echo "[DONE] Now restart UI + hard refresh"
