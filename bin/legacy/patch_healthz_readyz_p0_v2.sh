#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_healthz_v2_${TS}"
echo "[BACKUP] $APP.bak_healthz_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

def strip_literal_backslash_n(text: str):
    lines = text.splitlines(True)
    out=[]
    rm=0
    for ln in lines:
        if re.match(r'^\s*\\n\s*$', ln):
            rm += 1
            continue
        out.append(ln)
    return "".join(out), rm

# (0) pre-clean
s, rm0 = strip_literal_backslash_n(s)

MARK="VSP_HEALTHZ_READYZ_P0_V2"
if MARK not in s:
    code = (
        "\n# --- " + MARK + ": commercial health endpoints ---\n"
        "@app.get(\"/healthz\")\n"
        "def vsp_healthz_p0_v2():\n"
        "    return \"ok\", 200\n\n"
        "@app.get(\"/readyz\")\n"
        "def vsp_readyz_p0_v2():\n"
        "    return {\"ok\": True}, 200\n"
    )
    m = re.search(r'(?m)^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
    ins = m.start() if m else len(s)
    s = s[:ins] + code + s[ins:]

# (1) post-clean (in case anything injected introduces literal \n)
s, rm1 = strip_literal_backslash_n(s)

p.write_text(s, encoding="utf-8")
print("[OK] removed literal \\\\n lines: pre=", rm0, "post=", rm1)
print("[OK] ensured", MARK)
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910"
