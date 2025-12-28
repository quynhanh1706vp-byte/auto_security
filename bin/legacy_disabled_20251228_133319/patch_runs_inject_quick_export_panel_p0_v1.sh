#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_quickexport_${TS}"
echo "[BACKUP] ${F}.bak_runs_quickexport_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_RUNS_QUICK_EXPORT_PANEL_P0_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

snippet = r'''
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
                    if not name.startswith("RUN_") and not name.startswith("VSP_CI_"):
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
            meta["status"]=status; meta["headers"]=headers; meta["exc_info"]=exc_info
            return lambda _x: None

        it = self.app(environ, sr)
        body=b""
        try:
            for c in it:
                if c: body += c
        finally:
            try:
                close=getattr(it,"close",None)
                if callable(close): close()
            except Exception:
                pass

        headers = meta.get("headers") or []
        ct=""
        for k,v in headers:
            if str(k).lower()=="content-type":
                ct=str(v); break

        if ("text/html" in ct) and (MARK.encode() not in body):
            runs=self._pick_runs(10)

            # NO <script>, NO <style> (avoid STRIP_PSCRIPT). Pure HTML.
            links=[]
            for rid in runs:
                links.append(
                    f'<div style="display:flex;gap:10px;align-items:center;'
                    f'padding:6px 0;border-bottom:1px solid rgba(255,255,255,.06);">'
                    f'<code style="opacity:.9">{rid}</code>'
                    f'<a href="/api/vsp/export_zip?run_id={rid}" '
                    f'style="margin-left:auto;text-decoration:none;display:inline-block;'
                    f'padding:7px 10px;border-radius:10px;font-weight:800;'
                    f'border:1px solid rgba(90,140,255,.35);background:rgba(90,140,255,.16);color:inherit;">'
                    f'Export ZIP</a>'
                    f'</div>'
                )

            panel = (
                f'\n<div id="{MARK}" data-vsp-marker="{MARK}" '
                f'style="margin:14px 0;padding:12px 14px;'
                f'border:1px solid rgba(255,255,255,.08);'
                f'border-radius:14px;background:rgba(255,255,255,.03);">'
                f'<div style="display:flex;align-items:center;gap:10px;margin-bottom:8px;">'
                f'<div style="font-weight:900;letter-spacing:.2px;">Quick Export ZIP</div>'
                f'<div style="opacity:.75;font-size:12px;">(latest runs, no-JS)</div>'
                f'</div>'
                f'{"".join(links) if links else "<div style=\\"opacity:.8\\">No RUN_* found.</div>"}'
                f'</div>\n'
            ).encode("utf-8","replace")

            if b"<body" in body:
                # inject right after <body ...>
                idx = body.lower().find(b">", body.lower().find(b"<body"))
                if idx != -1:
                    body = body[:idx+1] + panel + body[idx+1:]
                else:
                    body = panel + body
            else:
                body = panel + body

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
'''
p.write_text(s.rstrip()+"\n\n"+snippet+"\n", encoding="utf-8")
print("[OK] appended MW quick-export panel")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
