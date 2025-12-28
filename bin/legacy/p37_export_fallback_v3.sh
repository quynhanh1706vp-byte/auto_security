#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need awk; need wc; need head
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl not found"; exit 2; }

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p37_export_v3_${TS}"
echo "[BACKUP] ${W}.bak_p37_export_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

def rm(marker):
    global s
    pat=re.compile(r"(?s)\n# --- "+re.escape(marker)+r" ---.*?\n# --- /"+re.escape(marker)+r" ---\n")
    s2,n=pat.subn("\n", s)
    if n:
        print("[OK] removed", marker, "x", n)
    s=s2

rm("VSP_P37_EXPORT_ENDPOINT_V1")
rm("VSP_P37_EXPORT_ENDPOINT_V2_FIXED")
rm("VSP_P37_EXPORT_ENDPOINT_V3_FALLBACK")

block = r'''
# --- VSP_P37_EXPORT_ENDPOINT_V3_FALLBACK ---
# Commercial P37: /api/vsp/export?rid=...&fmt=html|pdf|zip
# If per-RID findings file missing => fallback to global UI findings_unified.json (still exports bytes>0).
__vsp_p37_export_installed = globals().get("__vsp_p37_export_installed", False)

def __vsp_p37_bytes(start_response, body: bytes, ctype: str, filename: str = "", code: int = 200):
    hdrs = [
        ("Content-Type", ctype),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store"),
    ]
    if filename:
        hdrs.append(("Content-Disposition", f'attachment; filename="{filename}"'))
    start_response(str(code) + " OK", hdrs)
    return [body]

def __vsp_p37_json(start_response, obj: dict, code: int = 200):
    import json, time
    if "ts" not in obj:
        obj["ts"] = int(time.time())
    body = (json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8", "replace")
    return __vsp_p37_bytes(start_response, body, "application/json; charset=utf-8", "", code)

def __vsp_p37_qs(environ):
    import urllib.parse
    return urllib.parse.parse_qs(environ.get("QUERY_STRING") or "")

def __vsp_p37_resolve_findings_file_for_rid(rid: str):
    import os
    if not rid:
        return None
    roots=[]
    for ev in ("VSP_OUT_CI_DIR","VSP_OUT_DIR","RUNS_ROOT","VSP_RUNS_ROOT"):
        v=os.environ.get(ev) or ""
        if v.strip():
            roots.append(v.strip())
    roots += [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    cand=[]
    for r in roots:
        cand += [
            os.path.join(r, rid, "findings_unified.json"),
            os.path.join(r, rid, "reports", "findings_unified.json"),
            os.path.join(r, rid, "report", "findings_unified.json"),
        ]
    for fp in cand:
        if os.path.isfile(fp):
            return fp
    return None

def __vsp_p37_load_items(fp: str):
    import json, os
    if not fp or not os.path.isfile(fp):
        return []
    try:
        j=json.load(open(fp,"r",encoding="utf-8"))
    except Exception:
        return []
    if isinstance(j, dict):
        it=j.get("items")
        return it if isinstance(it, list) else []
    if isinstance(j, list):
        return j
    return []

def __vsp_p37_escape(s: str) -> str:
    return (s or "").replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;")

def __vsp_p37_make_html(rid: str, fp: str, items: list, note: str="") -> bytes:
    head = f"""<!doctype html><html><head><meta charset="utf-8">
<title>VSP Export {__vsp_p37_escape(rid)}</title>
<style>
body{{font-family:Arial,Helvetica,sans-serif;margin:16px;background:#0b1220;color:#e5e7eb}}
h1{{font-size:18px;margin:0 0 8px 0}}
small{{color:#9ca3af}}
table{{width:100%;border-collapse:collapse;margin-top:12px;font-size:12px}}
th,td{{border:1px solid #23324a;padding:6px;vertical-align:top}}
th{{background:#101b31}}
code{{color:#93c5fd}}
</style></head><body>"""
    meta = f"<h1>VSP Export</h1><small>RID: <code>{__vsp_p37_escape(rid)}</code> | source: <code>{__vsp_p37_escape(fp)}</code> | total: {len(items)}"
    if note:
        meta += f" | note: <code>{__vsp_p37_escape(note)}</code>"
    meta += "</small>"
    rows=[]
    for i, it in enumerate(items[:200]):
        if not isinstance(it, dict):
            continue
        sev = __vsp_p37_escape(str(it.get("severity","")))
        title = __vsp_p37_escape(str(it.get("title","") or it.get("message","") or ""))
        file = __vsp_p37_escape(str(it.get("file","")))
        tool = __vsp_p37_escape(str(it.get("tool","")))
        rule = __vsp_p37_escape(str(it.get("rule_id","")))
        line = __vsp_p37_escape(str(it.get("line","")))
        rows.append(f"<tr><td>{i+1}</td><td>{tool}</td><td>{sev}</td><td>{rule}</td><td>{title}</td><td>{file}:{line}</td></tr>")
    table = "<table><thead><tr><th>#</th><th>Tool</th><th>Sev</th><th>Rule</th><th>Title</th><th>Location</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>"
    return (head + meta + table + "</body></html>").encode("utf-8","replace")

def __vsp_p37_make_pdf_minimal(rid: str, total: int, note: str="") -> bytes:
    txt1 = "VSP Export"
    txt2 = f"RID: {rid}   TOTAL: {total}"
    txt3 = (f"NOTE: {note}" if note else "")
    def esc(t): return t.replace("\\","\\\\").replace("(","\\(").replace(")","\\)")
    txt1, txt2, txt3 = esc(txt1), esc(txt2), esc(txt3)
    content = f"BT /F1 16 Tf 72 740 Td ({txt1}) Tj ET\nBT /F1 12 Tf 72 720 Td ({txt2}) Tj ET\n"
    if txt3:
        content += f"BT /F1 10 Tf 72 700 Td ({txt3}) Tj ET\n"
    content_bytes = content.encode("latin-1","replace")
    parts=[]
    parts.append(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    xref=[]
    def obj(n, b):
        xref.append(len(b"".join(parts)))
        parts.append(f"{n} 0 obj\n".encode("ascii")+b+b"\nendobj\n")
    obj(1, b"<< /Type /Catalog /Pages 2 0 R >>")
    obj(2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    obj(3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>")
    obj(4, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    obj(5, b"<< /Length "+str(len(content_bytes)).encode("ascii")+b" >>\nstream\n"+content_bytes+b"endstream")
    xref_pos = len(b"".join(parts))
    parts.append(b"xref\n0 6\n0000000000 65535 f \n")
    parts.append(b"0000000000 00000 n \n")
    for off in xref:
        parts.append(f"{off:010d} 00000 n \n".encode("ascii"))
    parts.append(b"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n")
    parts.append(str(xref_pos).encode("ascii")+b"\n%%EOF\n")
    return b"".join(parts)

def __vsp_p37_make_zip(fp: str, html: bytes) -> bytes:
    import io, zipfile, os
    bio=io.BytesIO()
    with zipfile.ZipFile(bio, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("report.html", html)
        if fp and os.path.isfile(fp):
            z.write(fp, arcname="findings_unified.json")
    return bio.getvalue()

try:
    if not __vsp_p37_export_installed:
        __vsp_app_prev_p37 = globals().get("__vsp_app_prev_p37")
        if __vsp_app_prev_p37 is None:
            __vsp_app_prev_p37 = globals().get("application")
            globals()["__vsp_app_prev_p37"] = __vsp_app_prev_p37

        if callable(__vsp_app_prev_p37) and not getattr(__vsp_app_prev_p37, "__vsp_p37__", False):

            def application(environ, start_response):
                try:
                    path = (environ.get("PATH_INFO") or "")
                    p = path[:-1] if (path.endswith("/") and path != "/") else path
                    method = (environ.get("REQUEST_METHOD") or "GET").upper()

                    if p == "/api/vsp/export" and method == "GET":
                        qs = __vsp_p37_qs(environ)
                        rid = (qs.get("rid", [""])[0] or "").strip()
                        fmt = (qs.get("fmt", [""])[0] or "html").strip().lower()
                        if not rid:
                            return __vsp_p37_json(start_response, {"ok": False, "reason": "missing_rid"})

                        fp = __vsp_p37_resolve_findings_file_for_rid(rid)
                        note = ""
                        if not fp:
                            # fallback to global UI findings file
                            g = "/home/test/Data/SECURITY_BUNDLE/ui/findings_unified.json"
                            fp = g
                            note = "rid_file_missing_fallback_to_global"

                        items = __vsp_p37_load_items(fp)
                        html = __vsp_p37_make_html(rid, fp, items, note)

                        if fmt == "html":
                            return __vsp_p37_bytes(start_response, html, "text/html; charset=utf-8", f"vsp_{rid}.html")
                        if fmt == "pdf":
                            pdf = __vsp_p37_make_pdf_minimal(rid, len(items), note)
                            return __vsp_p37_bytes(start_response, pdf, "application/pdf", f"vsp_{rid}.pdf")
                        if fmt == "zip":
                            z = __vsp_p37_make_zip(fp, html)
                            return __vsp_p37_bytes(start_response, z, "application/zip", f"vsp_{rid}.zip")

                        return __vsp_p37_json(start_response, {"ok": False, "rid": rid, "reason": "invalid_fmt", "fmt": fmt})

                except Exception as e:
                    return __vsp_p37_json(start_response, {"ok": False, "reason": "exception", "error": str(e)})

                return __vsp_app_prev_p37(environ, start_response)

            application.__vsp_p37__ = True
            globals()["__vsp_p37_export_installed"] = True
except Exception:
    pass
# --- /VSP_P37_EXPORT_ENDPOINT_V3_FALLBACK ---
'''

s = s.rstrip() + "\n" + block + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended: VSP_P37_EXPORT_ENDPOINT_V3_FALLBACK")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [restart] =="
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" || true

echo "== [warm] =="
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 2 --max-time 4 "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
    echo "[OK] selfcheck ok (try#$i)"; break
  fi
  sleep 0.2
done

echo "== [CHECK export quick] =="
RID="VSP_CI_20251211_133204"
for fmt in html pdf zip; do
  echo "-- fmt=$fmt --"
  curl -sS --connect-timeout 2 --max-time 25 -D /tmp/_e.hdr -o /tmp/_e.bin \
    "$BASE/api/vsp/export?rid=$RID&fmt=$fmt" || true
  awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:|^Content-Length:/{print}' /tmp/_e.hdr
  echo "bytes=$(wc -c </tmp/_e.bin 2>/dev/null || echo 0)"
  head -c 80 /tmp/_e.bin; echo; echo
done
