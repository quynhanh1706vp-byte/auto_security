#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_KILL_DEGRADEDCHECK_V2"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_killdeg_${TS}"
echo "[BACKUP] ${JS}.bak_killdeg_${TS}"

python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, re

js_path = sys.argv[1]
mark = sys.argv[2]
p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

def brace_span(src, start_idx):
    # find first '{' after start_idx, then brace-count to end
    i = src.find("{", start_idx)
    if i < 0: return None
    depth = 0
    for j in range(i, len(src)):
        c = src[j]
        if c == "{": depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return (start_idx, j+1)
    return None

# 1) Replace function body with no-op (robust: handles "function __vspCheckDegraded" and "window.__vspCheckDegraded = function")
starts = []
for m in re.finditer(r'\bfunction\s+__vspCheckDegraded\s*\([^)]*\)\s*', s):
    starts.append(m.start())
for m in re.finditer(r'window\.__vspCheckDegraded\s*=\s*function\s*\([^)]*\)\s*', s):
    starts.append(m.start())

if starts:
    # take first occurrence
    st = min(starts)
    span = brace_span(s, st)
    if span:
        a,b = span
        # decide stub form based on original prefix
        head = s[a:s.find("{", a)]
        if head.strip().startswith("window.__vspCheckDegraded"):
            stub = "window.__vspCheckDegraded = function(){ /* disabled */ return; }"
        else:
            stub = "function __vspCheckDegraded(){ /* disabled */ return; }"
        s = s[:a] + "\n/* ===================== VSP_P3_KILL_DEGRADEDCHECK_V2 ===================== */\n" + stub + "\n/* ===================== /VSP_P3_KILL_DEGRADEDCHECK_V2 ===================== */\n" + s[b:]
    else:
        print("[WARN] found start but cannot parse braces; will still patch listeners")
else:
    # if not found, we still patch listeners and insert a safe global no-op at top
    s = "window.__vspCheckDegraded = function(){ return; };\n" + s

# 2) Remove any DOMContentLoaded listeners that reference __vspCheckDegraded (many variants)
lines = s.splitlines(True)
out = []
for ln in lines:
    if ("DOMContentLoaded" in ln and "__vspCheckDegraded" in ln and "addEventListener" in ln):
        out.append("/* VSP_P3_KILL_DEGRADEDCHECK_V2: removed listener */\n")
    else:
        out.append(ln)
s = "".join(out)

# 3) Also neutralize direct calls like "__vspCheckDegraded();" on load
s = re.sub(r'__vspCheckDegraded\s*\(\s*\)\s*;', '/* VSP_P3_KILL_DEGRADEDCHECK_V2: call removed */', s)

# 4) marker footer
s += f"\n/* {mark} */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker present =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing"; exit 2; }

echo "[DONE] degraded-check killed. HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
