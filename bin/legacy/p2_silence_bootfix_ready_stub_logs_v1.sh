#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_p2_silence_stublog_${TS}"
echo "[BACKUP] ${WSGI}.bak_p2_silence_stublog_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_SILENCE_BOOTFIX_READY_STUBLOG_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

def gate_print(indent: str, tag: str) -> str:
    # Only print when VSP_DEBUG_STUBLOG=1, and only once per process.
    return textwrap.dedent(f"""
    {indent}import os
    {indent}_VSP_ONCE_FLAGS = globals().setdefault("_VSP_ONCE_FLAGS", {{}})
    {indent}if os.environ.get("VSP_DEBUG_STUBLOG", "") == "1" and not _VSP_ONCE_FLAGS.get("{tag}", 0):
    {indent}    print
    """).rstrip("\n")

def replace_prints(prefix: str, once_key: str) -> None:
    global s
    # Replace any print line like:
    #   print("[VSP_BOOTFIX] ...", repr(e))
    # with a gated-print-once block.
    pat = re.compile(r'^(?P<i>[ \t]*)print\(\s*"\[' + re.escape(prefix) + r'\][^"]*".*\)\s*$', re.M)
    def repl(m):
        ind = m.group("i")
        line = m.group(0).strip()
        # guarded block: keep original print but behind env + once
        block = (
            f'{ind}import os\n'
            f'{ind}_VSP_ONCE_FLAGS = globals().setdefault("_VSP_ONCE_FLAGS", {{}})\n'
            f'{ind}if os.environ.get("VSP_DEBUG_STUBLOG", "") == "1" and not _VSP_ONCE_FLAGS.get("{once_key}", 0):\n'
            f'{ind}    {line}\n'
            f'{ind}    _VSP_ONCE_FLAGS["{once_key}"] = 1'
        )
        return block
    s2 = pat.sub(repl, s)
    s = s2

# target both old + new messages (failed / skipped)
replace_prints("VSP_BOOTFIX", "p2_stublog_bootfix")
replace_prints("VSP_READY_STUB", "p2_stublog_ready")

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK)
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
fi

echo
echo "== VERIFY endpoints still OK =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -s -o /dev/null -w "GET /ready => %{http_code}\n" "$BASE/ready" || true
curl -s -o /dev/null -w "GET /readyz => %{http_code}\n" "$BASE/readyz" || true
curl -s -o /dev/null -w "GET /healthz => %{http_code}\n" "$BASE/healthz" || true

echo
echo "== RECENT LOG (should be quiet unless VSP_DEBUG_STUBLOG=1) =="
journalctl -u "$SVC" --no-pager -n 120 | egrep "VSP_BOOTFIX|VSP_READY_STUB" || echo "(quiet)"
