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

cp -f "$W" "${W}.bak_p3k26_v6_${TS}"
echo "[BACKUP] ${W}.bak_p3k26_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

TAG="P3K26_DEDUPE_MARKERS_FORCE_HTML_V6"
if TAG in s:
    print("[OK] already patched (no-op)")
    raise SystemExit(0)

# 1) DEDUPE: any place doing resp.headers['X-VSP-MARKERS-...']=... should be guarded
# Best-effort: replace direct set with "if not in headers: set"
def guard_header_set(txt):
    # matches: resp.headers["X-..."] = "..."
    pat = r'(?m)^(?P<ind>\s*)(?P<obj>\w+)\.headers\[(?P<q>["\'])(?P<h>X-VSP-MARKERS-[^"\']+)(?P=q)\]\s*=\s*(?P<val>.+?)\s*$'
    def repl(m):
        ind=m.group("ind"); obj=m.group("obj"); h=m.group("h"); val=m.group("val")
        return (f"{ind}# {TAG}: dedupe marker header\n"
                f"{ind}try:\n"
                f"{ind}    if '{h}' not in {obj}.headers:\n"
                f"{ind}        {obj}.headers['{h}'] = {val}\n"
                f"{ind}except Exception:\n"
                f"{ind}    pass")
    return re.sub(pat, repl, txt)

s2 = guard_header_set(s)

# 2) FORCE HTML on /vsp5 if route returns JSON (safety net)
# Insert into after_request injector function (by marker) a conversion:
MARK="VSP_P2_VSP5_ANCHOR_INJECT_AFTERREQ_SAFE_V2"
mi = s2.find(MARK)
if mi < 0:
    print("[WARN] cannot find afterreq marker to force HTML; only dedupe applied")
else:
    # insert right after marker line (not top-level): find enclosing def
    lines = s2.splitlines(True)
    m_idx = next(i for i,ln in enumerate(lines) if MARK in ln)
    # find nearest def above
    def_idx=None
    for j in range(m_idx, -1, -1):
        if lines[j].lstrip().startswith("def ") and lines[j].rstrip().endswith(":"):
            def_idx=j; break
    if def_idx is None:
        raise SystemExit("[ERR] cannot find enclosing def for afterreq marker")

    def_indent = len(lines[def_idx]) - len(lines[def_idx].lstrip())
    body_indent = def_indent + 4

    # figure response var name if possible, else fallback to locals scan (like v5)
    m = re.search(r'^\s*def\s+\w+\s*\((.*)\)\s*:\s*$', lines[def_idx])
    params = (m.group(1) if m else "")
    # naive: first param name
    resp_var = None
    if params:
        first = params.split(",")[0].strip()
        first = first.split(":")[0].strip()
        first = first.split("=")[0].strip()
        if re.match(r'^[A-Za-z_]\w*$', first):
            resp_var = first

    pad = " " * body_indent
    get_resp = resp_var or "(__import__('inspect').currentframe().f_locals.get('response') or __import__('inspect').currentframe().f_locals.get('resp') or __import__('inspect').currentframe().f_locals.get('r'))"
    snippet = (
        f"{pad}# {TAG}: force /vsp5 to return HTML shell (never JSON)\n"
        f"{pad}try:\n"
        f"{pad}    from flask import request as _r\n"
        f"{pad}    _resp = {get_resp}\n"
        f"{pad}    if (_r.path or '') == '/vsp5' and _resp is not None:\n"
        f"{pad}        _ct = (_resp.headers.get('Content-Type','') if hasattr(_resp,'headers') else '')\n"
        f"{pad}        if 'application/json' in _ct:\n"
        f"{pad}            _html = '<!doctype html><html><head><meta charset=\"utf-8\"><title>VSP Dashboard</title></head><body><div id=\"vsp-dashboard-main\"></div><script>location.replace(\"/vsp5\");</script></body></html>'\n"
        f"{pad}            try:\n"
        f"{pad}                _resp.set_data(_html.encode('utf-8'))\n"
        f"{pad}                _resp.headers['Content-Type'] = 'text/html; charset=utf-8'\n"
        f"{pad}            except Exception:\n"
        f"{pad}                pass\n"
        f"{pad}except Exception:\n"
        f"{pad}    pass\n"
    )
    # insert after def/docstring
    ins=def_idx+1
    while ins < len(lines) and lines[ins].strip()=="":
        ins+=1
    if ins < len(lines) and lines[ins].lstrip().startswith(('"""',"'''")):
        q=lines[ins].lstrip()[:3]; ins+=1
        while ins < len(lines) and q not in lines[ins]:
            ins+=1
        if ins < len(lines): ins+=1
    lines.insert(ins, snippet)
    s2 = "".join(lines)
    print("[OK] inserted force-HTML snippet into after_request")

p.write_text(s2, encoding="utf-8")
print("[OK] wrote gateway v6")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== smoke headers =="
curl -sS -D- --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html | sed -n '1,60p'
echo "== content-type =="
grep -i '^content-type:' -n /tmp/vsp5.html >/dev/null 2>&1 || true
