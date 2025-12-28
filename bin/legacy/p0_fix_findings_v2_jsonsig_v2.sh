#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_jsonsigfix_${TS}"
echo "[BACKUP] ${F}.bak_jsonsigfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_FIX_JSONSIG_DROP_START_RESPONSE_V2"

# 1) Fix all call-sites: __vsp__json(start_response, ...)  --> __vsp__json(...)
# This keeps remaining args intact, so:
#   __vsp__json(start_response, payload)       -> __vsp__json(payload)
#   __vsp__json(start_response, payload, 200)  -> __vsp__json(payload, 200)
pat = re.compile(r'__vsp__json\(\s*start_response\s*,\s*')
s2, n = pat.subn('__vsp__json(', s)
print("[OK] rewired __vsp__json(start_response, ...) -> __vsp__json(...):", n)

# 2) Ensure __wsgi_json exists (avoid NameError) – safe fallback returning Werkzeug Response
if marker not in s2:
    block = textwrap.dedent(r"""
    # --- VSP_P0_FIX_JSONSIG_DROP_START_RESPONSE_V2 ---
    # Ensure __wsgi_json exists (avoid NameError in __vsp__json).
    try:
        __wsgi_json  # noqa: F401
    except Exception:
        try:
            # __Response and __json are already used inside __vsp__json fallback in this file
            def __wsgi_json(payload, status=200, mimetype="application/json"):  # noqa: F811
                try:
                    return __Response(__json.dumps(payload, ensure_ascii=False), status=status, mimetype=mimetype)
                except TypeError:
                    # last-resort: stringify non-serializable objects
                    return __Response(__json.dumps(payload, ensure_ascii=False, default=str), status=status, mimetype=mimetype)
        except Exception:
            pass
    """).strip() + "\n"
    s2 = s2.rstrip() + "\n\n" + block
    print("[OK] appended marker block:", marker)
else:
    print("[SKIP] marker already present")

p.write_text(s2, encoding="utf-8")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service

echo "== verify findings_v2 =="
BASE=http://127.0.0.1:8910
RID=$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("items",[{}])[0].get("run_id",""))')
echo "[RID]=$RID"
curl -sS -i "$BASE/api/ui/findings_v2?rid=$RID&limit=5&offset=0&q=" | sed -n '1,25p'
