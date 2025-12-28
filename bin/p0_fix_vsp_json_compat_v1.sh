#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_json_compat_${TS}"
echo "[BACKUP] ${F}.bak_json_compat_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_JSON_COMPAT_ADAPTER_V1"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# --- VSP_P0_JSON_COMPAT_ADAPTER_V1 ---
# Fix TypeError: __vsp__json() takes 1-2 args but some call sites pass 3 (start_response, payload, status).
# We keep original implementation and add a compat adapter that supports:
#   - __vsp__json(payload)
#   - __vsp__json(payload, status)
#   - __vsp__json(start_response, payload)
#   - __vsp__json(start_response, payload, status)
try:
    __vsp__json__orig = __vsp__json  # type: ignore[name-defined]
    def __vsp__json(*args, **kwargs):  # noqa: F811
        # Prefer explicit kw if provided
        if kwargs:
            return __vsp__json__orig(*args, **kwargs)

        # 3-args legacy: (start_response, payload, status)
        if len(args) == 3:
            _sr, _payload, _status = args
            # Most common modern form is (payload, status)
            try:
                return __vsp__json__orig(_payload, _status)
            except TypeError:
                # fallback: (start_response, payload)
                return __vsp__json__orig(_sr, _payload)

        # 2-args: could be (payload, status) OR (start_response, payload)
        if len(args) == 2:
            a0, a1 = args
            # if first arg is callable => likely start_response
            if callable(a0):
                try:
                    return __vsp__json__orig(a0, a1)
                except TypeError:
                    return __vsp__json__orig(a1)
            return __vsp__json__orig(a0, a1)

        # 1-arg or 0-arg
        return __vsp__json__orig(*args)
except Exception:
    pass
""").strip() + "\n"

p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
print("[OK] appended:", marker)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
echo "sudo systemctl restart vsp-ui-8910.service"

echo "== verify after restart =="
echo "BASE=http://127.0.0.1:8910"
echo 'RID=$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get(\"items\",[{}])[0].get(\"run_id\",\"\"))")'
echo 'curl -sS -i "$BASE/api/ui/findings_v2?rid=$RID&limit=5&offset=0&q=" | sed -n "1,12p"'
