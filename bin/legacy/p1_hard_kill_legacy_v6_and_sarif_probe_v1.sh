#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

B="static/js/vsp_bundle_commercial_v2.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

cp -f "$B" "${B}.bak_killv6_${TS}"
echo "[BACKUP] ${B}.bak_killv6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_HARD_KILL_LEGACY_V6_AND_SARIF_PROBE_V1"
if MARK not in s:
    s = f"""/* {MARK}
 * Hard-disable legacy V6C/V6D/V6E runners + block SARIF probe.
 */\n""" + s

# --- helper: locate enclosing IIFE / function block and insert unconditional return;
def wrap_block_unconditional(text: str, needle: str, tag: str) -> str:
    idx = text.find(needle)
    if idx < 0:
        return text

    starts = [
        "(()=>", "(() =>", "(function", "function", "async function",
    ]
    start = -1
    for st in starts:
        start = text.rfind(st, 0, idx)
        if start >= 0:
            break
    if start < 0:
        return text

    brace = text.find("{", start)
    if brace < 0 or brace > idx:
        return text

    # avoid double-inject
    window = text[start: min(len(text), brace+2000)]
    if f"HARD_DISABLED_{tag}" in window:
        return text

    inject = f"\n/* HARD_DISABLED_{tag} */\nreturn; // hard-disabled\n"
    return text[:brace+1] + inject + text[brace+1:]

# --- Hard kill legacy V6* blocks by their log strings (exact as seen in console)
needles = [
    ("[VSP][DASH] legacy disabled (V6E)", "V6E"),
    ("[VSP][DASH] legacy disabled (V6C)", "V6C"),
    ("[VSP][DASH] legacy disabled (V6D)", "V6D"),
]

for needle, tag in needles:
    for _ in range(0, 80):  # keep wrapping until stable
        before = s
        s = wrap_block_unconditional(s, needle, tag)
        if s == before:
            break

# --- Block SARIF probe:
# 1) Replace direct probeText(...findings_unified.sarif...) with Promise.resolve(false)
s = re.sub(r'probeText\s*\(([^;]*?findings_unified\.sarif[^;]*?)\)',
           'Promise.resolve(false) /* sarif probe disabled */',
           s)

# 2) If there is still a hardcoded string, rename it so it won't be fetched by code that builds URL from it
s = s.replace("findings_unified.sarif", "findings_unified.sarif__DISABLED__")

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$B" && echo "[OK] node --check passed"
fi

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
