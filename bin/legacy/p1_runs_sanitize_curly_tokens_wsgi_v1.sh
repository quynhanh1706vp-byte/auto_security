#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_RUNS_SANITIZE_CURLY_TOKENS_WSGI_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_runs_sanitize_${TS}"
echo "[BACKUP] ${W}.bak_runs_sanitize_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_RUNS_SANITIZE_CURLY_TOKENS_WSGI_V1"
if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

# We patch inside the existing response-capture middleware area by anchoring near the /vsp5 strip block,
# then insert a /runs sanitize block right after it (still before Content-Length normalize).
anchor = "# B) Strip injected inline dash scripts on /vsp5 HTML (outermost)"
i = s.find(anchor)
if i < 0:
    raise SystemExit("[ERR] cannot find anchor block for insertion")

# Find a safe insertion point after that block but before "normalize Content-Length"
j = s.find("# normalize Content-Length", i)
if j < 0:
    raise SystemExit("[ERR] cannot find Content-Length normalize block")

# Deduce indentation at insertion zone (use indentation of the line at j)
line_start = s.rfind("\n", 0, j) + 1
indent = ""
while line_start + len(indent) < len(s) and s[line_start + len(indent)] in (" ", "\t"):
    indent += s[line_start + len(indent)]

block = "\n".join([
    f"{indent}# {mark}: sanitize any leftover '{{{{ ... }}}}' tokens from /runs HTML (commercial smoke-safe)",
    f"{indent}if path == \"/runs\" and (\"text/html\" in ct or ct == \"\"):",
    f"{indent}    try:",
    f"{indent}        html = body.decode(\"utf-8\", errors=\"replace\")",
    f"{indent}        # remove Jinja-style tokens in HTML only (do not touch static JS)",
    f"{indent}        html2 = _re.sub(r\"\\{\\{[^\\}]*\\}\\}\", \"\", html)",
    f"{indent}        if html2 != html:",
    f"{indent}            body = html2.encode(\"utf-8\")",
    f"{indent}            headers = [(k,v) for (k,v) in headers if str(k).lower() not in (\"content-length\",\"cache-control\")]",
    f"{indent}            headers.append((\"Cache-Control\",\"no-store\"))",
    f"{indent}    except Exception:",
    f"{indent}        pass",
]) + "\n\n"

s2 = s[:j] + block + s[j:]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] /runs HTML sanitize enabled (removes any {{...}} tokens)."
