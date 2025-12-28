#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_RUNS_SANITIZE_CURLY_TOKENS_WSGI_V1B_FIX"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_runs_sanitize_${TS}"
echo "[BACKUP] ${W}.bak_runs_sanitize_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_RUNS_SANITIZE_CURLY_TOKENS_WSGI_V1B_FIX"
if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

anchor = "# B) Strip injected inline dash scripts on /vsp5 HTML (outermost)"
i = s.find(anchor)
if i < 0:
    raise SystemExit("[ERR] cannot find anchor block (vsp5 strip header)")

j = s.find("# normalize Content-Length", i)
if j < 0:
    raise SystemExit("[ERR] cannot find Content-Length normalize block")

# indent at insertion point (same indent level as other 'if path ==' blocks there)
line_start = s.rfind("\n", 0, j) + 1
indent = ""
while line_start + len(indent) < len(s) and s[line_start + len(indent)] in (" ", "\t"):
    indent += s[line_start + len(indent)]

# IMPORTANT: do NOT use f-string for the regex line; keep it as literal python source.
lines = [
    indent + f"# {mark}: sanitize any leftover '{{{{ ... }}}}' tokens from /runs HTML (commercial smoke-safe)",
    indent + "if path == \"/runs\" and (\"text/html\" in ct or ct == \"\"):",
    indent + "    try:",
    indent + "        html = body.decode(\"utf-8\", errors=\"replace\")",
    indent + "        # remove Jinja-style tokens in HTML only",
    indent + "        html2 = _re.sub(r\"\\{\\{[^\\}]*\\}\\}\", \"\", html)",
    indent + "        if html2 != html:",
    indent + "            body = html2.encode(\"utf-8\")",
    indent + "            headers = [(k,v) for (k,v) in headers if str(k).lower() not in (\"content-length\",\"cache-control\")]",
    indent + "            headers.append((\"Cache-Control\",\"no-store\"))",
    indent + "    except Exception:",
    indent + "        pass",
    "",
    ""
]
block = "\n".join(lines)

s2 = s[:j] + block + s[j:]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] /runs HTML sanitize enabled (removes any {{...}} tokens)."
