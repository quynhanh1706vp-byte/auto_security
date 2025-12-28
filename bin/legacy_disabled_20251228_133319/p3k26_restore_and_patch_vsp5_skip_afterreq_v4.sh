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

echo "== [1] pick latest clean backup =="
BAK="$(ls -1t "${W}.bak_p3k26_vsp5hang_"* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] cannot find backup ${W}.bak_p3k26_vsp5hang_*"; exit 2; }
echo "[OK] backup=$BAK"

echo "== [2] restore =="
cp -f "$BAK" "$W"
echo "[OK] restored $W"

echo "== [3] patch: skip after_request injector on /vsp5 (safe insert inside function) =="
python3 - <<'PY'
from pathlib import Path
import re

W = Path("wsgi_vsp_ui_gateway.py")
lines = W.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK_AFTER = "VSP_P2_VSP5_ANCHOR_INJECT_AFTERREQ_SAFE_V2"
TAG_AFTER  = "P3K26_SKIP_AFTERREQ_V4"
MARK_WRAP  = "VSP_P2_VSP5_ANCHOR_WSGI_WRAP_V1"
TAG_WRAP   = "P3K26_VSP5_PASSTHRU_V4"

def find_marker_idx(mark: str):
    for i, ln in enumerate(lines):
        if mark in ln:
            return i
    return None

def find_enclosing_def(start_idx: int):
    """Find nearest preceding 'def name(...):' line"""
    for j in range(start_idx, -1, -1):
        ln = lines[j]
        if ln.lstrip().startswith("def ") and ln.rstrip().endswith(":"):
            return j
    return None

def insertion_point_after_def(def_idx: int):
    """Insert after def line + optional docstring + blank lines"""
    def_indent = len(lines[def_idx]) - len(lines[def_idx].lstrip())
    body_indent = def_indent + 4
    k = def_idx + 1
    # skip blanks
    while k < len(lines) and lines[k].strip() == "":
        k += 1
    # skip docstring
    if k < len(lines) and lines[k].lstrip().startswith(('"""',"'''")):
        q = lines[k].lstrip()[:3]
        k += 1
        while k < len(lines) and q not in lines[k]:
            k += 1
        if k < len(lines):
            k += 1
    return k, body_indent

changed = False

# ---- Patch AFTER_REQUEST injector ----
if any(TAG_AFTER in ln for ln in lines):
    print("[OK] after_request already patched (no-op)")
else:
    mi = find_marker_idx(MARK_AFTER)
    if mi is None:
        print("[WARN] after_request marker not found, skip patch")
    else:
        di = find_enclosing_def(mi)
        if di is None:
            raise SystemExit("[ERR] cannot locate enclosing def for after_request marker")
        # get first arg name (response variable) to return correctly
        m = re.search(r'^(\s*)def\s+\w+\s*\(\s*([A-Za-z_]\w*)', lines[di])
        if not m:
            raise SystemExit("[ERR] cannot parse after_request def signature")
        resp_var = m.group(2)
        ins, body_indent = insertion_point_after_def(di)
        pad = " " * body_indent
        snippet = (
            f"{pad}# {TAG_AFTER}: /vsp5 must NOT run injector (avoid hang)\n"
            f"{pad}try:\n"
            f"{pad}    from flask import request as _r\n"
            f"{pad}    if (_r.path or '') == '/vsp5':\n"
            f"{pad}        return {resp_var}\n"
            f"{pad}except Exception:\n"
            f"{pad}    pass\n"
        )
        lines.insert(ins, snippet)
        changed = True
        print(f"[OK] patched after_request at def line {di+1}, resp_var={resp_var}")

# ---- Patch WSGI WRAP passthru (optional safety) ----
if any(TAG_WRAP in ln for ln in lines):
    print("[OK] wrap already patched (no-op)")
else:
    mw = find_marker_idx(MARK_WRAP)
    if mw is None:
        print("[WARN] wrap marker not found, skip wrap passthru")
    else:
        # find wrapper def(environ, start_response) after marker
        wrap_idx = None
        for i in range(mw, min(len(lines), mw + 5000)):
            ln = lines[i]
            if ln.lstrip().startswith("def ") and ("environ" in ln and "start_response" in ln) and ln.rstrip().endswith(":"):
                wrap_idx = i
                break
        if wrap_idx is not None:
            def_indent = len(lines[wrap_idx]) - len(lines[wrap_idx].lstrip())
            body_indent = def_indent + 4
            ins, _ = insertion_point_after_def(wrap_idx)
            pad = " " * body_indent
            # best-effort target name inside wrapper
            look = "".join(lines[wrap_idx: min(len(lines), wrap_idx + 250)])
            target = "_app" if "_app(" in look or " _app" in look else "app"
            snippet = (
                f"{pad}# {TAG_WRAP}: /vsp5 passthrough before any wrap logic\n"
                f"{pad}try:\n"
                f"{pad}    if (environ.get('PATH_INFO') or '') == '/vsp5':\n"
                f"{pad}        return {target}(environ, start_response)\n"
                f"{pad}except Exception:\n"
                f"{pad}    pass\n"
            )
            lines.insert(ins, snippet)
            changed = True
            print(f"[OK] patched wrapper at line {wrap_idx+1}, target={target}")
        else:
            print("[WARN] cannot find def(environ, start_response) after wrap marker")

if changed:
    W.write_text("".join(lines), encoding="utf-8")
    print("[OK] wrote patched gateway")
else:
    print("[WARN] no changes applied")
PY

echo "== [4] py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [5] restart =="
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

echo "[DONE] p3k26_restore_and_patch_vsp5_skip_afterreq_v4"
