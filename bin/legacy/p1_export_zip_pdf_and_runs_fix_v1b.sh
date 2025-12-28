#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need grep; need python3; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

MARK="VSP_P1_EXPORT_ZIP_PDF_AND_RUNS_FIX_WSGI_V1B"
if grep -q "$MARK" "$F"; then
  echo "[OK] marker already present: $MARK"
else
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$F" "${F}.bak_export_zip_pdf_runs_v1b_${TS}"
  echo "[BACKUP] ${F}.bak_export_zip_pdf_runs_v1b_${TS}"

  cat >> "$F" <<'PY'
# ===================== VSP_P1_EXPORT_ZIP_PDF_AND_RUNS_FIX_WSGI_V1B =====================
# Commercial-safe WSGI intercept:
#  - GET /runs                       -> never zero-length (serves template or fallback)
#  - GET /api/vsp/run_export_zip?rid=RUN_... -> evidence zip bundle (attachment)
#  - GET /api/vsp/run_export_pdf?rid=RUN_... -> minimal executive PDF (attachment)
#
# No Flask route dependency. Never crashes gunicorn. No-store headers.

def _vsp_exp2_no_store(extra=None):
    h = [("Cache-Control","no-store"),("Pragma","no-cache"),("Expires","0")]
    if extra:
        h.extend(extra)
    return h

def _vsp_exp2_resp(start_response, status, body, ctype, extra=None):
    if body is None:
        body = b""
    hdr = [("Content-Type", ctype), ("Content-Length", str(len(body)))]
    hdr += _vsp_exp2_no_store(extra)
    start_response(status, hdr)
    return [body]

def _vsp_exp2_json(start_response, obj):
    import json
    b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    return _vsp_exp2_resp(start_response, "200 OK", b, "application/json; charset=utf-8")

def _vsp_exp2_qs(environ):
    from urllib.parse import parse_qs
    return parse_qs(environ.get("QUERY_STRING") or "", keep_blank_values=True)

def _vsp_exp2_safe_rid(rid):
    import re
    if not isinstance(rid, str):
        return None
    rid = rid.strip()
    if re.match(r"^RUN_\d{8}_\d{6}([A-Za-z0-9_.-]+)?$", rid):
        return rid
    return None

def _vsp_exp2_guess_run_dir(rid):
    import os
    from pathlib import Path
    roots = []
    env_root = os.environ.get("VSP_OUT_ROOT") or os.environ.get("SECURITY_BUNDLE_OUT_ROOT")
    if env_root:
        roots.append(env_root)
    roots += [
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]
    for r in roots:
        pr = Path(r)
        cand = pr / rid
        if cand.is_dir():
            return cand
    # fuzzy prefix
    for r in roots:
        pr = Path(r)
        if not pr.is_dir():
            continue
        try:
            cands = sorted(pr.glob(rid + "*"), key=lambda x: x.stat().st_mtime if x.exists() else 0, reverse=True)
            for c in cands:
                if c.is_dir():
                    return c
        except Exception:
            pass
    return None

def _vsp_exp2_runs_html_bytes():
    import time
    from pathlib import Path
    cands = [
        "templates/vsp_runs_reports_v1.html",
        "templates/vsp_runs_reports.html",
        "templates/vsp_runs.html",
    ]
    for c in cands:
        f = Path(c)
        if f.exists():
            html = f.read_text(encoding="utf-8", errors="replace")
            v = str(int(time.time()))
            html = html.replace("{{ asset_v }}", v).replace("{{asset_v}}", v)
            return html.encode("utf-8")
    return b"<!doctype html><html><head><meta charset='utf-8'><title>Runs</title></head><body><h3>Runs page template not found</h3><p>Go to <a href='/vsp5'>/vsp5</a></p></body></html>"

def _vsp_exp2_collect_files(run_dir, max_bytes=50*1024*1024):
    from pathlib import Path
    rd = Path(str(run_dir))
    prefer = [
        "run_manifest.json","run_evidence_index.json","run_gate.json","run_gate_summary.json",
        "findings_unified.json","findings_unified.sarif","findings_unified.csv",
        "rule_overrides_applied.json","reports/rule_overrides_applied.json",
        "reports/findings_unified.json","reports/findings_unified.sarif","reports/findings_unified.csv",
    ]
    files = []
    for rel in prefer:
        f = rd / rel
        if f.exists() and f.is_file():
            files.append(f)
    for relroot in ["reports","evidence"]:
        d = rd / relroot
        if d.exists() and d.is_dir():
            for f in sorted(d.rglob("*")):
                if f.is_file():
                    files.append(f)
    # dedup
    seen=set(); uniq=[]
    for f in files:
        try:
            key=str(f.resolve())
        except Exception:
            key=str(f)
        if key in seen: continue
        seen.add(key); uniq.append(f)

    final=[]; skipped=[]
    for f in uniq:
        try:
            sz=f.stat().st_size
            rel=str(f.relative_to(rd))
            if sz>max_bytes:
                skipped.append({"path":rel,"size":sz,"reason":"too_large"})
                continue
            final.append({"rel":rel,"abs":str(f),"size":sz})
        except Exception:
            skipped.append({"path":str(f),"reason":"stat_failed"})
    return final, skipped

def _vsp_exp2_make_zip(run_dir, rid):
    import io, json, time, zipfile
    from pathlib import Path
    rd = Path(str(run_dir))
    files, skipped = _vsp_exp2_collect_files(rd)
    note = {
        "rid": rid,
        "run_dir": str(rd),
        "exported_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "files_count": len(files),
        "skipped": skipped,
        "policy": {"max_file_bytes": 50*1024*1024},
    }
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("_export_note.json", json.dumps(note, ensure_ascii=False, indent=2))
        for it in files:
            try:
                z.write(it["abs"], arcname=it["rel"])
            except Exception:
                pass
    return buf.getvalue()

def _vsp_exp2_pdf_minimal(title, lines):
    # Minimal PDF generator (Helvetica), no external deps.
    # Enough for executive summary export.
    def esc(x):
        x = (x or "")
        return x.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")[:140]

    y=760
    stream=[f"BT /F1 14 Tf 50 {y} Td ({esc(title)}) Tj ET"]
    y-=24
    for ln in lines[:32]:
        stream.append(f"BT /F1 10 Tf 50 {y} Td ({esc(ln)}) Tj ET")
        y-=14
    stream_bytes=("\n".join(stream)).encode("utf-8")

    objs=[]
    objs.append(b"1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n")
    objs.append(b"2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n")
    objs.append(b"3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources<< /Font<< /F1 4 0 R >> >> /Contents 5 0 R >>endobj\n")
    objs.append(b"4 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj\n")
    objs.append(("5 0 obj<< /Length %d >>stream\n" % len(stream_bytes)).encode("ascii") + stream_bytes + b"\nendstream\nendobj\n")

    header=b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
    out=bytearray(); out+=header
    offsets=[0]
    for o in objs:
        offsets.append(len(out))
        out+=o
    xref_pos=len(out)
    out+=b"xref\n0 6\n"
    out+=b"0000000000 65535 f \n"
    for off in offsets[1:]:
        out+=("%010d 00000 n \n" % off).encode("ascii")
    out+=b"trailer<< /Size 6 /Root 1 0 R >>\nstartxref\n"
    out+=(str(xref_pos).encode("ascii")+b"\n%%EOF\n")
    return bytes(out)

def _vsp_exp2_make_pdf(run_dir, rid):
    import json
    from pathlib import Path
    rd = Path(str(run_dir))
    gate={}
    for cand in ["run_gate.json","reports/run_gate.json"]:
        f=rd/cand
        if f.exists():
            try:
                gate=json.loads(f.read_text(encoding="utf-8", errors="replace"))
                break
            except Exception:
                pass
    overall = gate.get("overall") or gate.get("overall_status") or "UNKNOWN"
    lines=[f"Run ID: {rid}", f"Run dir: {rd}", f"Overall: {overall}"]
    return _vsp_exp2_pdf_minimal("VSP Executive Summary", lines)

class _VSPExportWSGI2:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        import time, traceback
        path = environ.get("PATH_INFO") or ""
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        if path == "/runs" and method == "GET":
            try:
                body = _vsp_exp2_runs_html_bytes()
                return _vsp_exp2_resp(start_response, "200 OK", body, "text/html; charset=utf-8")
            except Exception as e:
                return _vsp_exp2_json(start_response, {"ok": False, "degraded": True, "error": str(e), "trace": traceback.format_exc()[-1000:], "ts": int(time.time())})

        if path == "/api/vsp/run_export_zip" and method == "GET":
            try:
                q=_vsp_exp2_qs(environ)
                rid=(q.get("rid") or [""])[0]
                rid2=_vsp_exp2_safe_rid(rid)
                if not rid2:
                    return _vsp_exp2_json(start_response, {"ok": False, "degraded": True, "error": "invalid_rid", "rid": rid, "ts": int(time.time())})
                rd=_vsp_exp2_guess_run_dir(rid2)
                if rd is None:
                    return _vsp_exp2_json(start_response, {"ok": False, "degraded": True, "error": "run_dir_not_found", "rid": rid2, "ts": int(time.time())})
                z=_vsp_exp2_make_zip(rd, rid2)
                fname = rid2 + "_evidence.zip"
                return _vsp_exp2_resp(start_response, "200 OK", z, "application/zip",
                                      extra=[("Content-Disposition", 'attachment; filename="%s"' % fname)])
            except Exception as e:
                return _vsp_exp2_json(start_response, {"ok": False, "degraded": True, "error": str(e), "trace": traceback.format_exc()[-1200:], "ts": int(time.time())})

        if path == "/api/vsp/run_export_pdf" and method == "GET":
            try:
                q=_vsp_exp2_qs(environ)
                rid=(q.get("rid") or [""])[0]
                rid2=_vsp_exp2_safe_rid(rid)
                if not rid2:
                    return _vsp_exp2_json(start_response, {"ok": False, "degraded": True, "error": "invalid_rid", "rid": rid, "ts": int(time.time())})
                rd=_vsp_exp2_guess_run_dir(rid2)
                if rd is None:
                    return _vsp_exp2_json(start_response, {"ok": False, "degraded": True, "error": "run_dir_not_found", "rid": rid2, "ts": int(time.time())})
                pdf=_vsp_exp2_make_pdf(rd, rid2)
                fname = rid2 + "_executive.pdf"
                return _vsp_exp2_resp(start_response, "200 OK", pdf, "application/pdf",
                                      extra=[("Content-Disposition", 'attachment; filename="%s"' % fname)])
            except Exception as e:
                return _vsp_exp2_json(start_response, {"ok": False, "degraded": True, "error": str(e), "trace": traceback.format_exc()[-1200:], "ts": int(time.time())})

        return self.inner(environ, start_response)

# Stackable wrap
try:
    application
except Exception:
    try:
        application = app
    except Exception:
        application = None

if application is not None:
    if not getattr(application, "_vsp_export2_wrapped", False):
        w = _VSPExportWSGI2(application)
        setattr(w, "_vsp_export2_wrapped", True)
        application = w
# ===================== /VSP_P1_EXPORT_ZIP_PDF_AND_RUNS_FIX_WSGI_V1B =====================
PY

  echo "[OK] appended $MARK to $F"
fi

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

# restart + verify
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null || true

BASE="http://127.0.0.1:8910"
echo "== HEAD /runs (should NOT be Content-Length: 0) =="
curl -sS -I "$BASE/runs" | sed -n '1,25p'

echo "== HEAD export ZIP/PDF (should be 200) =="
curl -sS -I "$BASE/api/vsp/run_export_zip?rid=RUN_20251120_130310" | sed -n '1,25p'
curl -sS -I "$BASE/api/vsp/run_export_pdf?rid=RUN_20251120_130310" | sed -n '1,25p'

echo "== PDF magic (should start with %PDF) =="
curl -sS "$BASE/api/vsp/run_export_pdf?rid=RUN_20251120_130310" | head -c 4; echo
