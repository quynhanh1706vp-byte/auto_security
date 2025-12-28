#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_quickexport_syntax_${TS}"
echo "[BACKUP] ${F}.bak_fix_quickexport_syntax_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

start = "# === VSP_RUNS_QUICK_EXPORT_PANEL_P0_V1 ==="
end   = "# === /VSP_RUNS_QUICK_EXPORT_PANEL_P0_V1 ==="

if start not in s or end not in s:
    raise SystemExit("[ERR] quick-export block not found; cannot patch safely")

fixed = r'''
# === VSP_RUNS_QUICK_EXPORT_PANEL_P0_V1 ===
class VSPRunsQuickExportPanelMWP0V1:
    def __init__(self, app):
        self.app = app

    def _pick_runs(self, limit=10):
        import os
        roots = [
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
        ]
        items=[]
        for root in roots:
            try:
                for name in os.listdir(root):
                    if not (name.startswith("RUN_") or name.startswith("VSP_CI_")):
                        continue
                    full=os.path.join(root,name)
                    if not os.path.isdir(full):
                        continue
                    try:
                        m=os.path.getmtime(full)
                    except Exception:
                        m=0
                    items.append((m,name))
            except Exception:
                pass

        items.sort(reverse=True, key=lambda x: x[0])
        seen=set()
        out=[]
        for _m, rid in items:
            if rid in seen:
                continue
            seen.add(rid)
            out.append(rid)
            if len(out) >= limit:
                break
        return out

    def __call__(self, environ, start_response):
        if (environ.get("PATH_INFO") or "") != "/runs":
            return self.app(environ, start_response)

        meta={}
        def sr(status, headers, exc_info=None):
            meta["status"]=status
            meta["headers"]=headers
            meta["exc_info"]=exc_info
            return lambda _x: None

        it = self.app(environ, sr)
        body=b""
        try:
            for c in it:
                if c:
                    body += c
        finally:
            try:
                close=getattr(it,"close",None)
                if callable(close):
                    close()
            except Exception:
                pass

        headers = meta.get("headers") or []
        ct=""
        for k,v in headers:
            if str(k).lower()=="content-type":
                ct=str(v); break

        MARK="VSP_RUNS_QUICK_EXPORT_PANEL_P0_V1"
        if ("text/html" in ct) and (MARK.encode() not in body):
            runs=self._pick_runs(10)

            links=[]
            for rid in runs:
                links.append(
                    '<div style="display:flex;gap:10px;align-items:center;'
                    'padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06);">'
                    f'<code style="opacity:.9">{rid}</code>'
                    f'<a href="/api/vsp/export_zip?run_id={rid}" '
                    'style="margin-left:auto;text-decoration:none;display:inline-block;'
                    'padding:7px 10px;border-radius:10px;font-weight:800;'
                    'border:1px solid rgba(90,140,255,.35);background:rgba(90,140,255,.16);color:inherit;">'
                    'Export ZIP</a>'
                    '</div>'
                )

            # IMPORTANT: avoid backslashes inside f-string expressions
            if links:
                content_html = "".join(links)
            else:
                content_html = '<div style="opacity:.8">No RUN_* found.</div>'

            panel_html = (
                f'\n<div id="{MARK}" data-vsp-marker="{MARK}" '
                'style="margin:14px 0;padding:12px 14px;'
                'border:1px solid rgba(255,255,255,.08);'
                'border-radius:14px;background:rgba(255,255,255,.03);">'
                '<div style="display:flex;align-items:center;gap:10px;margin-bottom:8px;">'
                '<div style="font-weight:900;letter-spacing:.2px;">Quick Export ZIP</div>'
                '<div style="opacity:.75;font-size:12px;">(latest runs, no-JS)</div>'
                '</div>'
                + content_html +
                '</div>\n'
            ).encode("utf-8","replace")

            # inject right after <body ...> if possible
            low = body.lower()
            bpos = low.find(b"<body")
            if bpos != -1:
                gt = low.find(b">", bpos)
                if gt != -1:
                    body = body[:gt+1] + panel_html + body[gt+1:]
                else:
                    body = panel_html + body
            else:
                body = panel_html + body

        newh=[]
        for k,v in headers:
            if str(k).lower()=="content-length":
                continue
            newh.append((k,v))
        newh.append(("Content-Length", str(len(body))))
        start_response(meta.get("status","200 OK"), newh, meta.get("exc_info"))
        return [body]

try:
    if "application" in globals():
        _a = globals().get("application")
        if _a is not None and not getattr(_a, "__VSP_RUNS_QUICK_EXPORT_PANEL_P0_V1__", False):
            _mw = VSPRunsQuickExportPanelMWP0V1(_a)
            setattr(_mw, "__VSP_RUNS_QUICK_EXPORT_PANEL_P0_V1__", True)
            globals()["application"] = _mw
except Exception:
    pass
# === /VSP_RUNS_QUICK_EXPORT_PANEL_P0_V1 ===
'''.strip()+"\n"

pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.DOTALL)
s2, n = pattern.subn(fixed, s)
if n != 1:
    raise SystemExit(f"[ERR] replace count={n}, expected 1")

p.write_text(s2, encoding="utf-8")
print("[OK] quick-export block replaced safely")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "[NEXT] restart + verify panel in /runs"
