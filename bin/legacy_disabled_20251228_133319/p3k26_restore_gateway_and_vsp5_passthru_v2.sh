#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ls >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [1] pick latest backup from p3k26 vsp5hang =="
BAK="$(ls -1t "${W}.bak_p3k26_vsp5hang_"* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] cannot find backup ${W}.bak_p3k26_vsp5hang_*"; exit 2; }
echo "[OK] backup=$BAK"

echo "== [2] restore clean gateway from backup =="
cp -f "$BAK" "$W"
echo "[OK] restored $W"

echo "== [3] patch safe vsp5 passthru at marker (no regex) =="
python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_VSP5_ANCHOR_WSGI_WRAP_V1"
TAG  = "P3K26_VSP5_PASSTHRU_V2"

if TAG in s:
    print("[OK] already patched passthru (no-op)")
else:
    i = s.find(MARK)
    if i < 0:
        raise SystemExit("[ERR] marker not found: %r" % MARK)

    # insert immediately after the marker line to keep syntax intact
    lines = s.splitlines(True)
    # find line index containing marker
    idx = next((k for k,ln in enumerate(lines) if MARK in ln), None)
    if idx is None:
        raise SystemExit("[ERR] marker line not found (unexpected)")

    snippet = (
        f"# {TAG}: /vsp5 must bypass WSGI wrap to avoid hangs\n"
        "try:\n"
        "    _pi = (environ.get('PATH_INFO') or '')\n"
        "    if _pi == '/vsp5':\n"
        "        # passthrough to underlying app\n"
        "        try:\n"
        "            _target = _app  # common name in this gateway\n"
        "        except Exception:\n"
        "            _target = app   # fallback name\n"
        "        return _target(environ, start_response)\n"
        "except Exception:\n"
        "    pass\n"
    )

    lines.insert(idx + 1, snippet)
    s2 = "".join(lines)
    p.write_text(s2, encoding="utf-8")
    print("[OK] inserted passthru snippet right after marker line")
PY

echo "== [4] syntax check =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [5] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [6] smoke /vsp5 (2s) =="
if command -v curl >/dev/null 2>&1; then
  curl -sv --connect-timeout 1 --max-time 2 "$BASE/vsp5" -o /tmp/vsp5.html \
    && echo "[OK] /vsp5 fetched => /tmp/vsp5.html" \
    || echo "[FAIL] /vsp5 still hanging"
fi

echo "[DONE] p3k26_restore_gateway_and_vsp5_passthru_v2"
