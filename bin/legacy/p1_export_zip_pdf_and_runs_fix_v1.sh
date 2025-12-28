#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_export_zip_pdf_runs_${TS}"
echo "[BACKUP] ${F}.bak_export_zip_pdf_runs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_EXPORT_ZIP_PDF_AND_RUNS_FIX_WSGI_V1"
if MARK in s:
    print("[OK] marker already present:", MARK)
    raise SystemExit(0)

BLOCK = textwrap.dedent(r"""
# ===================== VSP_P1_EXPORT_ZIP_PDF_AND_RUNS_FIX_WSGI_V1 =====================
# Adds commercial-safe WSGI intercept for:
#  - GET /api/vsp/run_export_zip?rid=RUN_...
#  - GET /api/vsp/run_export_pdf?rid=RUN_...
#  - GET /runs (avoid zero-length; serve template file with asset_v replacement)
#
# Always safe, never crashes gunicorn, never 404 for these endpoints once patched.

def _vsp_exp_no_store_headers(extra=None):
    h = [
        ("Cache-Control","no-store"),
        ("Pragma","no-cache"),
        ("Expires","0"),
        ("Connection","keep-alive"),
    ]
    if extra:
        h.extend(extra)
    return h

def _vsp_exp_resp_bytes(start_response, status, body_bytes, content_type, extra_headers=None):
    headers = [("Content-Type", content_type), ("Content-Length", str(len(body_bytes)))]
    headers = headers + _vsp_exp_no_store_headers(extra_headers)
    start_response(status, headers)
    return [body_bytes]

def _vsp_exp_resp_json(start_response, payload):
    import json
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    return _vsp_exp_resp_bytes(start_response, "200 OK", body, "application/json; charset=utf-8")

def _vsp_exp_query(environ):
    from urllib.parse import parse_qs
    qs = environ.get("QUERY_STRING") or ""
    return parse_qs(qs, keep_blank_values=True)

def _vsp_exp_safe_rid(rid):
    import re
    if not isinstance(rid, str):
        return None
    rid = rid.strip()
    # allow common run ids: RUN_YYYYmmdd_HHMMSS or RUN_xxx suffix
    if re.match(r"^RUN_\d{8}_\d{6}([A-Za-z0-9_.-]+)?$", rid):
        return rid
    return None

def _vsp_exp_guess_run_dir(rid):
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
    # fuzzy by prefix
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

def _vsp_exp_collect_files(run_dir, max_file_bytes=50*1024*1024):
    """
    Collect a curated set of files for ISO/DevSecOps evidence.
    Skips very large files (records skips into note).
    """
    from pathlib import Path
    files = []
    skipped = []
    rd = Path(str(run_dir))

    # prefer key audit files
    prefer = [
        "run_manifest.json",
        "run_evidence_index.json",
        "run_gate.json",
        "run_gate_summary.json",
        "findings_unified.json",
        "findings_unified.sarif",
        "findings_unified.csv",
        "rule_overrides_applied.json",
        "reports/rule_overrides_applied.json",
        "reports/findings_unified.json",
        "reports/findings_unified.csv",
        "reports/findings_unified.sarif",
    ]
    for rel in prefer:
        f = rd / rel
        if f.exists() and f.is_file():
            files.append(f)

    # add reports/* and evidence/* if exist
    for relroot in ["reports", "evidence"]:
        d = rd / relroot
        if d.exists() and d.is_dir():
            for f in sorted(d.rglob("*")):
                if f.is_file():
                    files.append(f)

    # de-dup
    seen = set()
    uniq = []
    for f in files:
        fp = str(f.resolve())
        if fp in seen:
            continue
        seen.add(fp)
        uniq.append(f)

    final = []
    for f in uniq:
        try:
            sz = f.stat().st_size
            if sz > max_file_bytes:
                skipped.append({"path": str(f.relative_to(rd)), "size": sz, "reason": "too_large"})
                continue
            final.append({"path": str(f.relative_to(rd)), "abs": str(f), "size": sz})
        except Exception:
            skipped.append({"path": str(f), "reason": "stat_failed"})
    return final, skipped

def _vsp_exp_make_zip_bytes(run_dir, rid):
    import io, json, time, zipfile
    from pathlib import Path

    rd = Path(str(run_dir))
    files, skipped = _vsp_exp_collect_files(rd)

    note = {
        "rid": rid,
        "run_dir": str(rd),
        "exported_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "files_count": len(files),
        "skipped": skipped,
        "policy": {"max_file_bytes": 50*1024*1024},
        "tips": [
            "This ZIP is an evidence bundle for audit/compliance (ISO 27001 / DevSecOps).",
            "If some large artifacts were skipped, retrieve them directly from run_dir."
        ]
    }

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("_export_note.json", json.dumps(note, ensure_ascii=False, indent=2))
        for it in files:
            rel = it["path"]
            try:
                z.write(it["abs"], arcname=rel)
            except Exception:
                # record failed add
                pass
    return buf.getvalue(), note

def _vsp_exp_pdf_minimal_bytes(title, lines):
    """
    Minimal PDF generator (Helvetica), no external deps.
    """
    import time

    # sanitize lines
    safe = []
    for x in lines:
        x = (x or "")
        x = x.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
        safe.append(x[:140])

    # build content stream
    y = 760
    stream_lines = [f"BT /F1 14 Tf 50 {y} Td ({title}) Tj ET"]
    y -= 24
    for ln in safe[:32]:
        stream_lines.append(f"BT /F1 10 Tf 50 {y} Td ({ln}) Tj ET")
        y -= 14

    stream = "\n".join(stream_lines).encode("utf-8")
    # basic PDF objects
    objs = []
    objs.append(b"1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n")
    objs.append(b"2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n")
    objs.append(b"3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources<< /Font<< /F1 4 0 R >> >> /Contents 5 0 R >>endobj\n")
    objs.append(b"4 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj\n")
    objs.append(f"5 0 obj<< /Length {len(stream)} >>stream\n".encode("ascii") + stream + b"\nendstream\nendobj\n")

    # xref
    header = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
    out = bytearray()
    out += header
    offsets = [0]
    for o in objs:
        offsets.append(len(out))
        out += o

    xref_pos = len(out)
    out += b"xref\n0 6\n"
    out += b"0000000000 65535 f \n"
    for off in offsets[1:]:
        out += f"{off:010d} 00000 n \n".encode("ascii")

    trailer = b"trailer<< /Size 6 /Root 1 0 R >>\nstartxref\n" + str(xref_pos).encode("ascii") + b"\n%%EOF\n"
    out += trailer
    return bytes(out)

def _vsp_exp_pdf_from_run(run_dir, rid):
    import json
    from pathlib import Path
    rd = Path(str(run_dir))
    gate = {}
    fg = {}
    # best-effort read
    for cand in ["run_gate.json", "reports/run_gate.json"]:
        f = rd / cand
        if f.exists():
            try:
                gate = json.loads(f.read_text(encoding="utf-8", errors="replace"))
                break
            except Exception:
                pass
    for cand in ["findings_unified.json", "reports/findings_unified.json"]:
        f = rd / cand
        if f.exists():
            try:
                fg = json.loads(f.read_text(encoding="utf-8", errors="replace"))
                break
            except Exception:
                pass

    overall = gate.get("overall") or gate.get("overall_status") or "UNKNOWN"
    lines = [
        f"Run ID: {rid}",
        f"Run dir: {rd}",
        f"Overall: {overall}",
    ]
    # counts if present
    sev = gate.get("by_severity") or gate.get("severity") or {}
    if isinstance(sev, dict) and sev:
        for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
            if k in sev:
                lines.append(f"Count {k}: {sev.get(k)}")
    # tool degraded hints
    bytool = gate.get("by_tool") or gate.get("tools") or {}
    if isinstance(bytool, dict) and bytool:
        dg = []
        for tn, tv in bytool.items():
            try:
                if isinstance(tv, dict) and (tv.get("degraded") or tv.get("status") == "DEGRADED"):
                    dg.append(tn)
            except Exception:
                pass
        if dg:
            lines.append("Degraded tools: " + ", ".join(sorted(dg)) )

    # findings meta
    if isinstance(fg, dict):
        items = fg.get("items") or fg.get("findings") or []
        if isinstance(items, list):
            lines.append(f"Findings total: {len(items)}")

    pdf = _vsp_exp_pdf_minimal_bytes("VSP Executive Summary", lines)
    return pdf

def _vsp_exp_read_text_file(path, default=""):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except Exception:
        return default

def _vsp_exp_runs_page_bytes():
    import time
    from pathlib import Path
    # prefer the known runs template
    cands = [
        "templates/vsp_runs_reports_v1.html",
        "templates/vsp_runs_reports.html",
        "templates/vsp_runs.html",
    ]
    for c in cands:
        f = Path(c)
        if f.exists():
            html = f.read_text(encoding="utf-8", errors="replace")
            # replace common jinja tokens if present
            v = str(int(time.time()))
            html = html.replace("{{ asset_v }}", v).replace("{{asset_v}}", v)
            return html.encode("utf-8")
    # fallback minimal
    return b"<!doctype html><html><head><meta charset='utf-8'><title>Runs</title></head><body><h3>Runs page template not found</h3><p>Go to <a href='/vsp5'>/vsp5</a>.</p></body></html>"

class _VSPExportWSGI:
    def __init__(self, inner_app):
        self.inner_app = inner_app

    def __call__(self, environ, start_response):
        import time, traceback
        path = environ.get("PATH_INFO") or ""
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        # Fix /runs zero-length + set no-store
        if path == "/runs" and method == "GET":
            try:
                body = _vsp_exp_runs_page_bytes()
                return _vsp_exp_resp_bytes(
                    start_response,
                    "200 OK",
                    body,
                    "text/html; charset=utf-8",
                    extra_headers=[("Cache-Control","no-store")]
                )
            except Exception as e:
                return _vsp_exp_resp_json(start_response, {"ok": False, "degraded": True, "error": str(e), "trace": traceback.format_exc()[-1200:], "ts": int(time.time())})

        # Export ZIP
        if path == "/api/vsp/run_export_zip" and method == "GET":
            try:
                q = _vsp_exp_query(environ)
                rid = (q.get("rid") or [""])[0]
                rid2 = _vsp_exp_safe_rid(rid)
                if not rid2:
                    return _vsp_exp_resp_json(start_response, {"ok": False, "degraded": True, "error": "invalid_rid", "rid": rid, "ts": int(time.time())})
                rd = _vsp_exp_guess_run_dir(rid2)
                if rd is None:
                    return _vsp_exp_resp_json(start_response, {"ok": False, "degraded": True, "error": "run_dir_not_found", "rid": rid2, "ts": int(time.time())})
                zbytes, note = _vsp_exp_make_zip_bytes(rd, rid2)
                fname = f"{rid2}_evidence.zip"
                return _vsp_exp_resp_bytes(
                    start_response,
                    "200 OK",
                    zbytes,
                    "application/zip",
                    extra_headers=[("Content-Disposition", f'attachment; filename="{fname}"')]
                )
            except Exception as e:
                return _vsp_exp_resp_json(start_response, {"ok": False, "degraded": True, "error": str(e), "trace": traceback.format_exc()[-1600:], "ts": int(time.time())})

        # Export PDF (minimal)
        if path == "/api/vsp/run_export_pdf" and method == "GET":
            try:
                q = _vsp_exp_query(environ)
                rid = (q.get("rid") or [""])[0]
                rid2 = _vsp_exp_safe_rid(rid)
                if not rid2:
                    return _vsp_exp_resp_json(start_response, {"ok": False, "degraded": True, "error": "invalid_rid", "rid": rid, "ts": int(time.time())})
                rd = _vsp_exp_guess_run_dir(rid2)
                if rd is None:
                    return _vsp_exp_resp_json(start_response, {"ok": False, "degraded": True, "error": "run_dir_not_found", "rid": rid2, "ts": int(time.time())})
                pdf = _vsp_exp_pdf_from_run(rd, rid2)
                fname = f"{rid2}_executive.pdf"
                return _vsp_exp_resp_bytes(
                    start_response,
                    "200 OK",
                    pdf,
                    "application/pdf",
                    extra_headers=[("Content-Disposition", f'attachment; filename="{fname}"')]
                )
            except Exception as e:
                return _vsp_exp_resp_json(start_response, {"ok": False, "degraded": True, "error": str(e), "trace": traceback.format_exc()[-1600:], "ts": int(time.time())})

        return self.inner_app(environ, start_response)

# Wrap exported application (stackable)
try:
    application
except Exception:
    try:
        application = app
    except Exception:
        application = None

if application is not None:
    if not getattr(application, "_vsp_export_wrapped_v1", False):
        wrapped = _VSPExportWSGI(application)
        setattr(wrapped, "_vsp_export_wrapped_v1", True)
        application = wrapped
# ===================== /VSP_P1_EXPORT_ZIP_PDF_AND_RUNS_FIX_WSGI_V1 =====================
""").strip("\n").replace("VSP_P1_EXPORT_ZIP_PDF_AND_RUNS_FIX_WSGI_V1", MARK)

m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
if m:
    s2 = s[:m.start()] + "\n\n" + BLOCK + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + BLOCK + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

# restart and quick verify
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null || true

BASE="http://127.0.0.1:8910"
echo "== HEAD /runs (must be non-zero + no-store) =="
curl -sS -I "$BASE/runs" | sed -n '1,20p'

echo "== HEAD export ZIP/PDF (must be 200) =="
curl -sS -I "$BASE/api/vsp/run_export_zip?rid=RUN_20251120_130310" | sed -n '1,20p'
curl -sS -I "$BASE/api/vsp/run_export_pdf?rid=RUN_20251120_130310" | sed -n '1,20p'

echo "== download smoke (just first bytes; should NOT be JSON) =="
curl -sS "$BASE/api/vsp/run_export_pdf?rid=RUN_20251120_130310" | head -c 8; echo
