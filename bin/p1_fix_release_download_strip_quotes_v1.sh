#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need grep; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_rel_stripq_${TS}"
echo "[BACKUP] ${WSGI}.bak_rel_stripq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_RELEASE_STRIP_QUOTES_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

# Patch 2 places inside VSP_P1_RELEASE_WSGI_MW_V1 where rid is read
# Replace: rid = (qs.get("rid",[""])[0] or "").strip()
# With:    rid = ...; rid = rid.strip().strip('"').strip("'")
needle = r'rid = (qs.get("rid",\[""\])\[0\] or "").strip\(\)'
repl = r'rid = (qs.get("rid",[""])[0] or "").strip(); rid = rid.strip().strip(\'"\').strip("\\\'")  # ' + MARK
s2, n = re.subn(needle, repl, s)
if n < 2:
    print("[WARN] expected >=2 replacements, got", n)
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK, "replacements=", n)
PY

systemctl restart "$SVC" || true
sleep 0.7

RID="$(curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[RID] $RID"
curl -fsS -o /tmp/vsp_release_test.zip "$BASE/api/vsp/release_download?rid=$RID"
echo "[OK] downloaded bytes=$(wc -c </tmp/vsp_release_test.zip)"
