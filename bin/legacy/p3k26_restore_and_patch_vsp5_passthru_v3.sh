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

echo "== [1] pick latest backup =="
BAK="$(ls -1t "${W}.bak_p3k26_vsp5hang_"* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] cannot find backup ${W}.bak_p3k26_vsp5hang_*"; exit 2; }
echo "[OK] backup=$BAK"

echo "== [2] restore clean gateway =="
cp -f "$BAK" "$W"
echo "[OK] restored $W"

echo "== [3] patch passthru inside wrapper function (safe) =="
python3 - <<'PY'
from pathlib import Path

TAG = "P3K26_VSP5_PASSTHRU_V3"
MARK = "VSP_P2_VSP5_ANCHOR_WSGI_WRAP_V1"

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

if any(TAG in ln for ln in lines):
    print("[OK] already patched (no-op)")
    raise SystemExit(0)

# find marker
m_idx = next((i for i,ln in enumerate(lines) if MARK in ln), None)
if m_idx is None:
    raise SystemExit(f"[ERR] marker not found: {MARK}")

# find nearest wrapper function after marker: def ...(environ, start_response)
wrap_idx = None
for i in range(m_idx, min(len(lines), m_idx + 4000)):
    ln = lines[i]
    if "def " in ln and ("environ" in ln and "start_response" in ln) and ln.lstrip().startswith("def "):
        wrap_idx = i
        break

if wrap_idx is None:
    # fallback: search entire file for wrapper signature
    for i, ln in enumerate(lines):
        if "def " in ln and ("environ" in ln and "start_response" in ln) and ln.lstrip().startswith("def "):
            wrap_idx = i
            break

if wrap_idx is None:
    raise SystemExit("[ERR] cannot locate wrapper def(environ, start_response) to patch safely")

def_indent = len(lines[wrap_idx]) - len(lines[wrap_idx].lstrip())
body_indent = def_indent + 4

# choose target callable name inside wrapper (best-effort)
# look ahead a bit: if "_app(" appears, use "_app", else "app"
look = "".join(lines[wrap_idx: min(len(lines), wrap_idx + 250)])
target = "_app" if "_app(" in look or " _app" in look else "app"

# find insertion point after def + optional docstring
ins = wrap_idx + 1
# skip blank lines
while ins < len(lines) and lines[ins].strip() == "":
    ins += 1
# skip docstring if present
if ins < len(lines) and lines[ins].lstrip().startswith(('"""',"'''")):
    q = lines[ins].lstrip()[:3]
    ins += 1
    while ins < len(lines) and q not in lines[ins]:
        ins += 1
    if ins < len(lines):
        ins += 1  # after closing quotes

pad = " " * body_indent
snippet = (
    f"{pad}# {TAG}: fast-path for /vsp5 to avoid wrap hang\n"
    f"{pad}try:\n"
    f"{pad}    if (environ.get('PATH_INFO') or '') == '/vsp5':\n"
    f"{pad}        return {target}(environ, start_response)\n"
    f"{pad}except Exception:\n"
    f"{pad}    pass\n"
)

lines.insert(ins, snippet)
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] inserted passthru into wrapper at line {wrap_idx+1}, target={target}")
PY

echo "== [4] py_compile =="
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

echo "[DONE] p3k26_restore_and_patch_vsp5_passthru_v3"
