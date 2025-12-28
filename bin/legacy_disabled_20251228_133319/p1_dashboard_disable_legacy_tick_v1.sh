#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && NODE_OK=1 || NODE_OK=0
command -v systemctl >/dev/null 2>&1 && SYS_OK=1 || SYS_OK=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P1_DASH_DISABLE_LEGACY_TICK_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_disable_tick_${TS}"
echo "[BACKUP] ${JS}.bak_disable_tick_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_DASH_DISABLE_LEGACY_TICK_V1"

changed = 0

# 1) Disable legacy 12s tick (hard stop)
pat_tick = r'^\s*setInterval\s*\(\s*tick\s*,\s*12000\s*\)\s*;\s*$'
s2, n = re.subn(pat_tick, '  /* {}: disabled legacy tick(12000) to prevent UI freeze */'.format(mark), s, flags=re.M)
if n:
    s = s2
    changed += n

# 2) Disable fallback counts from findings_unified meta (if present)
# Replace the comment line with a "disabled" marker AND guard any immediate block with "if(false)"
# This is safer than trying to delete unknown braces.
pat_fallback_comment = r'(^\s*//\s*4\)\s*fallback counts from findings_unified meta.*$)'
def repl(m):
    return m.group(1) + "\n    /* {}: DISABLED fallback to findings_unified meta (counts_total comes from run_gate_summary) */\n    if(false){".format(mark)
s2, n = re.subn(pat_fallback_comment, repl, s, flags=re.M)
if n:
    s = s2
    changed += n
    # close the injected if(false){ ... } at the next blank line after a "const fu = await" or after 25 lines
    lines = s.splitlines(True)
    out=[]
    i=0
    while i < len(lines):
        out.append(lines[i])
        if "if(false){" in lines[i] and mark in lines[i-1] if i>0 else False:
            # find a good closing spot soon
            j = i+1
            closed = False
            for k in range(j, min(j+60, len(lines))):
                if re.search(r'findings_unified\.json', lines[k]):
                    # close after the next line that looks like a block end or after a couple lines
                    # We'll close right after the next line that starts with "}" at same indent, else after 12 lines.
                    pass
            # simple: close after 18 lines to avoid breaking structure; best-effort
            for k in range(i+1, min(i+20, len(lines))):
                if re.match(r'^\s*//', lines[k]):  # next section starts
                    out.append("    }\n")
                    closed = True
                    i = k-1
                    break
            if not closed:
                out.append("    }\n")
        i += 1
    s = "".join(out)

# 3) Clamp any findings_unified fetch without limit to limit=25
# Replace occurrences of ...path=findings_unified.json` with ...path=findings_unified.json&limit=25`
# Works for both template literals and normal strings.
s2, n = re.subn(r'(path=findings_unified\.json)(?![^\n]{0,120}limit=)', r'\1&limit=25', s)
if n:
    s = s2
    changed += n

if changed == 0 and mark in s:
    print("[OK] already patched:", mark)
elif changed == 0:
    print("[WARN] no matching legacy tick/fallback found to patch (file may differ).")
else:
    # add a small marker near top for traceability
    if mark not in s:
        s = s.replace("/*", "/* {} */\n/*".format(mark), 1) if "/*" in s else ("/* {} */\n".format(mark) + s)
    p.write_text(s, encoding="utf-8")
    print("[OK] patched:", mark, "changed=", changed)
PY

if [ "$NODE_OK" = "1" ]; then
  node --check "$JS" >/dev/null && echo "[OK] node --check ok: $JS" || { echo "[ERR] node --check failed: $JS"; exit 3; }
fi

if [ "$SYS_OK" = "1" ]; then
  systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
fi

echo "[DONE] legacy tick disabled + findings_unified clamped."
