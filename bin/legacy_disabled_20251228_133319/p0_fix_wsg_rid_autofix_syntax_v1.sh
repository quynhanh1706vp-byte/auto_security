#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need grep; need sed; need awk

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_fix_rid_autofix_syntax_${TS}"
echo "[BACKUP] ${WSGI}.bak_fix_rid_autofix_syntax_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Normalize wrong token "{ asset_v }" -> "{{ asset_v }}"
s = s.replace("?v={ asset_v }", "?v={{ asset_v }}")

needle = 'vsp_rid_autofix_v1.js'
if needle not in s:
    print("[OK] rid autofix js not found in WSGI => nothing to fix")
    p.write_text(s, encoding="utf-8")
    sys.exit(0)

# 2) If the file contains a broken multi-line python string that starts with: script = '  <script src="/static/js/vsp_rid_autofix_v1.js...
#    cut it safely up to the end of the script tag.
start_pat = re.compile(r"^[ \t]*script\s*=\s*'\s*<script[^\\n]*" + re.escape(needle), re.M)
m = start_pat.search(s)
if not m:
    # Sometimes it starts with: script = '  <script src="..."
    start_pat2 = re.compile(r"^[ \t]*script\s*=\s*'[^\\n]*" + re.escape(needle), re.M)
    m = start_pat2.search(s)

if not m:
    # As a fallback, just fix any single-line assignment that lacks closing quote (rare)
    # We will not overreach; keep file untouched.
    print("[WARN] Found vsp_rid_autofix_v1.js but cannot locate the injected `script = '...` block start safely.")
    print("[HINT] Open around the injection and ensure the line is: script = '  <script ...></script>\\n'")
    p.write_text(s, encoding="utf-8")
    sys.exit(0)

# Determine indentation
line_start = s.rfind("\n", 0, m.start()) + 1
indent = re.match(r"[ \t]*", s[line_start:m.start()]).group(0)

# Find end of the broken script tag
end_tag = "</script>"
end_pos = s.find(end_tag, m.start())
if end_pos == -1:
    print("[ERR] Cannot find </script> after injected block; refusing to patch blindly.")
    sys.exit(2)

# Move to end-of-line after </script>
eol = s.find("\n", end_pos)
if eol == -1:
    eol = len(s)
else:
    eol = eol + 1

replacement = (
    f"{indent}# VSP_P0_RID_AUTOFIX_WSGI_PATCH_V1\n"
    f"{indent}script = '  <script src=\"/static/js/vsp_rid_autofix_v1.js?v={{ asset_v }}\"></script>\\n'\n"
)

s2 = s[:line_start] + replacement + s[eol:]

p.write_text(s2, encoding="utf-8")
print("[OK] patched broken rid autofix `script = ...` block -> single-line safe string")
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== restart service =="
systemctl restart "$SVC" || true

echo "== status (short) =="
systemctl --no-pager --full status "$SVC" | sed -n '1,18p' || true

echo
echo "[VERIFY] grep script tags from /vsp5 (after restart):"
echo "  curl -fsS http://127.0.0.1:8910/vsp5 | grep -nE 'vsp_rid_autofix_v1|gate_story_v1' || true"
