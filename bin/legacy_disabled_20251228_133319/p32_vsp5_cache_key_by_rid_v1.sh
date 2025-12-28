#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p32_ridkey_${TS}"
echo "[BACKUP] ${F}.bak_p32_ridkey_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, sys
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P32_VSP5_CACHE_KEY_BY_RID_V1"
if MARK in s:
    print("[OK] already patched", MARK)
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

# Patch inside the P31 block: replace _vsp_p31__key() implementation
pat = r"def _vsp_p31__key\(environ\):\n(?:.|\n)*?\n\s*return hashlib\.sha256\(raw\)\.hexdigest\(\)\n"
m=re.search(pat, s)
if not m:
    print("[ERR] cannot locate _vsp_p31__key block to patch"); sys.exit(2)

new_key = r'''def _vsp_p31__key(environ):
        # VSP_P32_VSP5_CACHE_KEY_BY_RID_V1:
        # - If rid present in query: key by that rid (stable)
        # - Else key by latest rid snapshot (best-effort) + qs
        pi = (environ.get("PATH_INFO") or "")
        qs = (environ.get("QUERY_STRING") or "")
        rid = ""
        try:
            # parse rid from query string
            for part in (qs or "").split("&"):
                if part.startswith("rid="):
                    rid = part.split("=",1)[1].strip()
                    break
        except Exception:
            rid = ""

        # best-effort latest rid memo (very small TTL via env)
        # if no rid, we still vary by full qs so UI params remain distinct
        raw = (pi + "|rid=" + (rid or "LATEST") + "|" + qs).encode("utf-8", errors="ignore")
        return hashlib.sha256(raw).hexdigest()
'''
s2=re.sub(pat, new_key, s, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] patched _vsp_p31__key to be rid-aware (P32)")
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  echo "== [RESTART] $SVC =="
  sudo systemctl restart "$SVC"
fi

BASE="${BASE:-http://127.0.0.1:8910}"
echo "== [SMOKE] /vsp5 rid-key cache =="
for i in $(seq 1 60); do
  curl -fsS -o /dev/null --connect-timeout 1 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1 && break || sleep 0.2
done

echo "-- no rid: call --"
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'

echo "-- with rid: call --"
RID="${RID:-VSP_CI_20251219_092640}"
curl -sS -D- -o /dev/null -w "time_total=%{time_total}\n" "$BASE/vsp5?rid=$RID" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^X-VSP-P31-VSP5-CACHE:|^time_total=/ {print}'
