#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_wsgijson_${TS}"
echo "[BACKUP] ${F}.bak_fix_wsgijson_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) restore __vsp__json to original (disable our compat adapters effect)
# We do NOT delete old blocks (safe), we just override at end to original.
marker_restore = "VSP_P0_RESTORE_VSP_JSON_ORIG_V1"
if marker_restore not in s:
    restore_block = textwrap.dedent(r"""
    # --- VSP_P0_RESTORE_VSP_JSON_ORIG_V1 ---
    # We previously added compat adapters that can return a Response object -> WSGI error: 'Response' not iterable.
    # Restore __vsp__json back to the original implementation if it was saved.
    try:
        # Prefer the earliest saved original if present
        _orig = globals().get("__vsp__json__orig")
        if callable(_orig):
            __vsp__json = _orig  # type: ignore[misc]
        else:
            _orig2 = globals().get("__vsp__json__orig2")
            if callable(_orig2):
                __vsp__json = _orig2  # type: ignore[misc]
    except Exception:
        pass
    """).strip() + "\n"
    s = s.rstrip() + "\n\n" + restore_block
    print("[OK] appended restore block")

# 2) fix legacy 3-arg call sites: __vsp__json(start_response, X, 200) -> __vsp__json(start_response, X)
# Keep conservative: only remove the trailing ", 200" (or ",200") just before ')'
pat = re.compile(r'__vsp__json\(\s*start_response\s*,\s*(.+?)\s*,\s*200\s*\)', re.DOTALL)
def repl(m):
    inner = m.group(1).strip()
    return f'__vsp__json(start_response, {inner})'

s2, n = pat.subn(repl, s)
print("[OK] rewired 3-arg __vsp__json(...,200) calls:", n)

p.write_text(s2, encoding="utf-8")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
echo "sudo systemctl restart vsp-ui-8910.service"

echo "== verify after restart =="
echo 'BASE=http://127.0.0.1:8910'
echo 'RID=$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c '\''import sys,json; d=json.load(sys.stdin); print(d.get("items",[{}])[0].get("run_id",""))'\'')'
echo 'curl -sS -i "$BASE/api/ui/findings_v2?rid=$RID&limit=5&offset=0&q=" | sed -n "1,20p"'
