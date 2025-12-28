#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need sed; need grep
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_p552_${TS}"
echo "[OK] backup => ${APP}.bak_p552_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# remove old "not allowed" stubs for these endpoints (if exist)
routes = [
  "export_html_v1","report_html_v1","export_report_v1","report_export_v1",
  "export_pdf_v1","report_pdf_v1"
]
pat = re.compile(
  r"(?ms)^@app\.route\([^\n]*?/api/vsp/(?:%s)[^\n]*\)\n.*?(?=^@app\.route|\Z)" % "|".join(routes)
)
s2 = pat.sub("", s)

new_block = r'''
# =========================
# P552: Commercial report export (HTML/PDF) by RID
# - fixes: /api/vsp/export_html_v1 etc returning {"err":"not allowed"}
# - behavior: return real HTML/PDF bytes (no external deps)
# =========================
import os, json, datetime
from pathlib import Path
from flask import request, Response, jsonify

def _p552_allow_export():
    # default allow in commercial local appliance
    # set VSP_UI_EXPORT_ALLOW=0 to hard-disable
    v = os.environ.get("VSP_UI_EXPORT_ALLOW", "1").strip().lower()
    return v not in ("0","false","no","off")

def _p552_resolve_run_dir(rid: str):
    if not rid or len(rid) > 120:
        return None
    # strict-ish: only safe chars
    if not re.match(r"^[A-Za-z0-9_\\-]+$", rid):
        return None

    roots = [
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
    ]
    # include cwd-relative (release layouts vary)
    roots += [Path.cwd() / "out_ci", Path.cwd() / "out"]

    for r in roots:
        d = r / rid
        if d.is_dir():
            return d

    # fallback: best-effort search shallow
    for r in roots:
        if not r.is_dir():
            continue
        try:
            for d in r.glob(f"**/{rid}"):
                if d.is_dir():
                    return d
        except Exception:
            pass
    return None

def _p552_find_first(run_dir: Path, names):
    # try direct common locations
    for rel in [
        Path("reports"),
        Path("report"),
        Path(""),
    ]:
        for nm in names:
            f = run_dir / rel / nm
            if f.is_file():
                return f
    # fallback search (depth)
    for nm in names:
        try:
            hits = list(run_dir.glob(f"**/{nm}"))
            hits = [h for h in hits if h.is_file()]
            if hits:
                # prefer shorter path
                hits.sort(key=lambda x: len(str(x)))
                return hits[0]
        except Exception:
            pass
    return None

def _p552_load_findings(run_dir: Path):
    fjson = _p552_find_first(run_dir, ["findings_unified.json", "findings.json"])
    if fjson:
        try:
            j = json.loads(fjson.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            j = None
        items = []
        if isinstance(j, dict):
            items = j.get("items") or j.get("findings") or j.get("results") or []
        elif isinstance(j, list):
            items = j
        if not isinstance(items, list):
            items = []
        return items, fjson

    # CSV fallback (very light)
    fcsv = _p552_find_first(run_dir, ["findings_unified.csv"])
    items = []
    if fcsv:
        try:
            import csv
            with open(fcsv, newline="", encoding="utf-8", errors="replace") as fp:
                rd = csv.DictReader(fp)
                for r in rd:
                    items.append(r)
        except Exception:
            pass
        return items, fcsv

    return [], None

def _p552_sev(x):
    # normalize to your 6-level scale
    v = ""
    if isinstance(x, dict):
        v = str(x.get("severity") or x.get("sev") or x.get("level") or "").upper()
    else:
        v = str(x).upper()
    if v in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"):
        return v
    # map common
    if v in ("ERROR","SEVERE"): return "HIGH"
    if v in ("WARN","WARNING"): return "MEDIUM"
    if v in ("DEBUG",): return "TRACE"
    return "INFO" if v else "INFO"

def _p552_counts(items):
    keys = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
    c = {k:0 for k in keys}
    for it in items:
        c[_p552_sev(it)] += 1
    return c

def _p552_html_escape(s: str):
    return (s or "").replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;")

def _p552_render_html(rid: str, items, counts, meta: dict):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    rows=[]
    # limit rows to keep size sane; UI report can paginate later
    for it in items[:5000]:
        if isinstance(it, dict):
            sev=_p552_sev(it)
            title=str(it.get("title") or it.get("message") or it.get("rule") or it.get("id") or "Finding")
            tool=str(it.get("tool") or it.get("scanner") or it.get("source") or "")
            loc=str(it.get("path") or it.get("file") or it.get("location") or "")
            cwe=str(it.get("cwe") or it.get("cwe_id") or "")
        else:
            sev="INFO"; title=str(it); tool=""; loc=""; cwe=""
        rows.append(f"<tr><td>{sev}</td><td>{_p552_html_escape(title)}</td><td>{_p552_html_escape(tool)}</td><td>{_p552_html_escape(loc)}</td><td>{_p552_html_escape(cwe)}</td></tr>")

    sevline = " | ".join([f"{k}:{counts.get(k,0)}" for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]])
    hdr = f"VSP Report — RID {rid}"
    rel_ts = _p552_html_escape(str(meta.get("release_ts","")))
    rel_sha = _p552_html_escape(str(meta.get("release_sha","")))

    html = f"""<!doctype html>
<html><head>
<meta charset="utf-8"/>
<title>{_p552_html_escape(hdr)}</title>
<style>
body{{font-family:Arial,Helvetica,sans-serif;margin:24px;}}
h1{{margin:0 0 6px 0;}}
.meta{{color:#444;font-size:12px;margin-bottom:16px;}}
.kpi{{display:flex;gap:10px;flex-wrap:wrap;margin:12px 0 14px 0;}}
.kpi div{{border:1px solid #ddd;padding:8px 10px;border-radius:8px;font-size:12px;}}
table{{border-collapse:collapse;width:100%;font-size:12px;}}
th,td{{border:1px solid #ddd;padding:6px 8px;vertical-align:top;}}
th{{background:#f3f3f3;text-align:left;}}
.small{{font-size:11px;color:#666;}}
</style>
</head><body>
<h1>{_p552_html_escape(hdr)}</h1>
<div class="meta">Generated: {now} &nbsp; | &nbsp; Release TS: {rel_ts} &nbsp; | &nbsp; Release SHA: {rel_sha}</div>
<div class="kpi">
  <div><b>CRITICAL</b><br>{counts.get("CRITICAL",0)}</div>
  <div><b>HIGH</b><br>{counts.get("HIGH",0)}</div>
  <div><b>MEDIUM</b><br>{counts.get("MEDIUM",0)}</div>
  <div><b>LOW</b><br>{counts.get("LOW",0)}</div>
  <div><b>INFO</b><br>{counts.get("INFO",0)}</div>
  <div><b>TRACE</b><br>{counts.get("TRACE",0)}</div>
</div>
<div class="small">Summary: {sevline}</div>
<h2>Findings</h2>
<table>
<thead><tr><th>Severity</th><th>Title</th><th>Tool</th><th>Location</th><th>CWE</th></tr></thead>
<tbody>
{''.join(rows) if rows else '<tr><td colspan="5">No findings</td></tr>'}
</tbody>
</table>
</body></html>"""
    return html

def _p552_simple_pdf_bytes(title: str, lines):
    # Minimal PDF writer (ASCII) — enough for gate + basic viewing
    # lines: list[str]
    def esc(s): return s.replace("\\","\\\\").replace("(","\\(").replace(")","\\)")
    content = []
    y = 800
    content.append("BT /F1 14 Tf 50 %d Td (%s) Tj ET" % (y, esc(title)))
    y -= 24
    for ln in lines[:200]:  # cap
        if y < 60: break
        content.append("BT /F1 10 Tf 50 %d Td (%s) Tj ET" % (y, esc(ln)))
        y -= 14
    stream = "\n".join(content).encode("ascii", errors="replace")

    objs = []
    def obj(i, b): objs.append((i,b))

    obj(1, b"<< /Type /Catalog /Pages 2 0 R >>")
    obj(2, b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    obj(3, b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>")
    obj(4, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    obj(5, b"<< /Length %d >>\nstream\n%s\nendstream" % (len(stream), stream))

    out = bytearray()
    out += b"%PDF-1.4\n"
    xref = [0]
    for i,b in objs:
        xref.append(len(out))
        out += (f"{i} 0 obj\n").encode()
        out += b + b"\nendobj\n"
    xref_pos = len(out)
    out += b"xref\n0 %d\n" % (len(objs)+1)
    out += b"0000000000 65535 f \n"
    for off in xref[1:]:
        out += ("%010d 00000 n \n" % off).encode()
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs)+1, xref_pos)
    return bytes(out)

def _p552_export_common(rid: str, fmt: str):
    if not _p552_allow_export():
        return jsonify({"ok": False, "err": "export_disabled"}), 403

    run_dir = _p552_resolve_run_dir(rid)
    if not run_dir:
        return jsonify({"ok": False, "err": "rid_not_found", "rid": rid}), 404

    items, src = _p552_load_findings(run_dir)
    counts = _p552_counts(items)
    meta = {
        "release_ts": request.headers.get("X-VSP-RELEASE-TS", "") or "",
        "release_sha": request.headers.get("X-VSP-RELEASE-SHA", "") or "",
    }
    # also pass through known release headers (if middleware adds them)
    if request:
        meta["release_ts"] = request.environ.get("HTTP_X_VSP_RELEASE_TS", meta["release_ts"])
        meta["release_sha"] = request.environ.get("HTTP_X_VSP_RELEASE_SHA", meta["release_sha"])

    if fmt == "html":
        html = _p552_render_html(rid, items, counts, meta)
        return Response(html, mimetype="text/html; charset=utf-8")

    if fmt == "pdf":
        title = f"VSP Report — {rid}"
        sevline = " ".join([f"{k}:{counts.get(k,0)}" for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]])
        lines = [f"RID: {rid}", f"Source: {src}", f"Summary: {sevline}"]
        # add a few findings lines
        for it in items[:50]:
            if isinstance(it, dict):
                sev=_p552_sev(it)
                t=str(it.get("title") or it.get("message") or it.get("rule") or it.get("id") or "Finding")
                lines.append(f"- [{sev}] {t[:120]}")
            else:
                lines.append(f"- {str(it)[:120]}")
        pdfb = _p552_simple_pdf_bytes(title, lines)
        return Response(pdfb, mimetype="application/pdf",
                        headers={"Content-Disposition": f'attachment; filename="report_{rid}.pdf"'})

    return jsonify({"ok": False, "err": "bad_fmt"}), 400

@app.route("/api/vsp/export_html_v1")
@app.route("/api/vsp/report_html_v1")
def api_vsp_export_html_v1():
    rid = request.args.get("rid","").strip()
    if not rid:
        return jsonify({"ok": False, "err": "missing_rid"}), 400
    return _p552_export_common(rid, "html")

@app.route("/api/vsp/export_pdf_v1")
@app.route("/api/vsp/report_pdf_v1")
def api_vsp_export_pdf_v1():
    rid = request.args.get("rid","").strip()
    if not rid:
        return jsonify({"ok": False, "err": "missing_rid"}), 400
    return _p552_export_common(rid, "pdf")

@app.route("/api/vsp/export_report_v1")
@app.route("/api/vsp/report_export_v1")
def api_vsp_export_report_v1():
    rid = request.args.get("rid","").strip()
    fmt = (request.args.get("fmt","html") or "html").strip().lower()
    if not rid:
        return jsonify({"ok": False, "err": "missing_rid"}), 400
    if fmt not in ("html","pdf"):
        return jsonify({"ok": False, "err": "bad_fmt", "fmt": fmt}), 400
    return _p552_export_common(rid, fmt)
'''

# insert before __main__ if present, else append
m = re.search(r"(?m)^if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s2)
if m:
    s_out = s2[:m.start()] + new_block + "\n\n" + s2[m.start():]
else:
    s_out = s2 + "\n\n" + new_block + "\n"

p.write_text(s_out, encoding="utf-8")
print("[OK] patched export routes")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile"

# restart service if possible
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

echo "== quick probe (html) =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251219_092640}"
curl -sS -D- --connect-timeout 2 --max-time 6 "$BASE/api/vsp/export_html_v1?rid=$RID" | head -n 15
echo "== quick probe (pdf magic) =="
curl -sS --connect-timeout 2 --max-time 6 "$BASE/api/vsp/export_pdf_v1?rid=$RID" | head -c 5; echo
