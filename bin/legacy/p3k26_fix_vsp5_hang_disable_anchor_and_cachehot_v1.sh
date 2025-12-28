#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_p3k26_vsp5hang_${TS}"
echo "[BACKUP] ${W}.bak_p3k26_vsp5hang_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

def patch_block(marker: str, label: str):
    global s
    # Wrap marker block with a quick no-op guard for /vsp5 to avoid hang.
    # We do it conservatively: if marker exists, we inject a guard right after the marker line.
    if marker not in s:
        return False
    # Insert a tiny guard comment + variable to allow grepping later.
    s2 = s.replace(marker, marker + "\n# P3K26_VSP5_HANG_FIX_V1: guard /vsp5 to avoid heavy inject/wrap\n")
    s = s2
    print(f"[OK] tagged marker: {label}")
    return True

changed = False

# 1) If these markers exist, tag them so we can locate and adjust logic safely.
changed |= patch_block("VSP_P2_VSP5_ANCHOR_INJECT_AFTERREQ_SAFE_V2", "after_request_inject")
changed |= patch_block("VSP_P2_VSP5_ANCHOR_WSGI_WRAP_V1", "wsgi_wrap")

# 2) Hard-disable common wrapper patterns for /vsp5 (best-effort regex).
# a) after_request injector: if code checks request.path=="/vsp5" and then mutates body, force skip.
s2 = re.sub(
    r'(?s)(#\s*P3K26_VSP5_HANG_FIX_V1: guard /vsp5 to avoid heavy inject/wrap\n.*?)(if\s+.*?request\.path\s*==\s*[\'"]\/vsp5[\'"].*?:)',
    r'\1# P3K26: force skip injector for /vsp5\nif False:\n    pass\n',
    s
)
if s2 != s:
    s = s2
    changed = True
    print("[OK] neutralized /vsp5 after_request injector (best-effort)")

# b) WSGI wrap: if wrapper checks PATH_INFO == '/vsp5', force direct passthrough.
s2 = re.sub(
    r'(?s)(def\s+.*?\(environ,\s*start_response\)\s*:\s*\n)(\s*.*?PATH_INFO.*?\/vsp5.*?\n)(\s*.*?return\s+.*?start_response.*?\n)',
    r'\1\2    # P3K26: passthrough for /vsp5 (avoid wrap hang)\n    return _app(environ, start_response)\n',
    s
)
if s2 != s:
    s = s2
    changed = True
    print("[OK] forced /vsp5 WSGI passthrough (best-effort)")

# 3) cachehot: if missing endpoint -> skip quickly (best-effort)
# Look for "cachehot" and "endpoint NOT FOUND" patterns and ensure it doesn't loop.
if "cachehot" in s:
    s2 = re.sub(
        r'(?m)^\s*(for\s+_.*in\s+range\(\s*\d+\s*\)\s*:\s*)$',
        r'# P3K26: avoid retry loops in cachehot\n# \1',
        s
    )
    if s2 != s:
        s = s2
        changed = True
        print("[OK] softened cachehot retry loops (best-effort)")

if not changed:
    print("[WARN] no matching patterns found; left file unchanged (safe no-op)")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] wrote patched gateway")
PY

echo "== py_compile =="
python3 -m py_compile "$W"

echo "== restart =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== smoke /vsp5 (2s) =="
if command -v curl >/dev/null 2>&1; then
  curl -sv --connect-timeout 1 --max-time 2 "$BASE/vsp5" -o /tmp/vsp5.html && echo "[OK] /vsp5 fetched to /tmp/vsp5.html" || echo "[FAIL] /vsp5 still hanging"
fi

echo "[DONE] p3k26_fix_vsp5_hang_disable_anchor_and_cachehot_v1"
