#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_fix_iframe_${TS}"
echo "[BACKUP] ${WSGI}.bak_fix_iframe_${TS}"

python3 - "$WSGI" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

# (1) Remove the broken inserted block (marker-based)
A="# --- VSP_P0_RUN_FILE_RAW_V1_IFRAME_SAMEORIGIN ---"
B="# --- /VSP_P0_RUN_FILE_RAW_V1_IFRAME_SAMEORIGIN ---"
removed=0
if A in s and B in s:
    pat=re.compile(re.escape(A)+r"[\s\S]*?"+re.escape(B)+r"\n?", re.M)
    s2, n = pat.subn("", s, count=1)
    if n:
        s=s2
        removed=1

# (2) Patch existing DENY header assignment to be conditional (raw => SAMEORIGIN)
# Find the line that sets X-Frame-Options = DENY and replace safely.
# Keep indentation exactly as original line.
m = re.search(r'(?m)^(?P<ind>\s*)resp\.headers\[\s*[\'"]X-Frame-Options[\'"]\s*\]\s*=\s*[\'"]DENY[\'"]\s*$', s)
patched=0
if m:
    ind=m.group("ind")
    repl = (
        ind + "try:\n"
        + ind + "    from flask import request as _req\n"
        + ind + "    _p = (_req.path or \"\")\n"
        + ind + "except Exception:\n"
        + ind + "    _p = \"\"\n"
        + ind + "resp.headers[\"X-Frame-Options\"] = \"SAMEORIGIN\" if _p.startswith(\"/api/vsp/run_file_raw_v1\") else \"DENY\""
    )
    s = s[:m.start()] + repl + s[m.end():]
    patched=1

p.write_text(s, encoding="utf-8")
print("[OK] removed_broken_block=", removed, "patched_xfo=", patched)
if not patched:
    print("[WARN] could not locate exact 'X-Frame-Options = DENY' line; header condition not patched")
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== verify header behavior (raw route should be SAMEORIGIN) =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -i -sS "$BASE/api/vsp/run_file_raw_v1?rid=$RID&path=run_gate_summary.json" | head -n 25 || true
