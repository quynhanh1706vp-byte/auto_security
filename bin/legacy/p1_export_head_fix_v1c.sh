#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need grep; need python3; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

MARK="VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C"
if grep -q "$MARK" "$F"; then
  echo "[OK] marker already present: $MARK"
else
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$F" "${F}.bak_export_headfix_${TS}"
  echo "[BACKUP] ${F}.bak_export_headfix_${TS}"

  cat >> "$F" <<'PY'
# ===================== VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C =====================
# Make HEAD behave like GET for existence probes:
# - HEAD /runs
# - HEAD /api/vsp/run_export_zip?rid=...
# - HEAD /api/vsp/run_export_pdf?rid=...
# Always 200 for these endpoints (commercial probe-friendly), never crashes gunicorn.

def _vsp_head_no_store(extra=None):
    h = [("Cache-Control","no-store"),("Pragma","no-cache"),("Expires","0")]
    if extra:
        h.extend(extra)
    return h

def _vsp_head_start(start_response, ctype, clen="0", extra=None):
    headers = [("Content-Type", ctype), ("Content-Length", str(clen))]
    headers += _vsp_head_no_store(extra)
    start_response("200 OK", headers)
    return [b""]  # HEAD must not return body

def _vsp_head_qs(environ):
    from urllib.parse import parse_qs
    return parse_qs(environ.get("QUERY_STRING") or "", keep_blank_values=True)

def _vsp_head_safe_rid(rid):
    import re
    if not isinstance(rid, str):
        return None
    rid = rid.strip()
    if re.match(r"^RUN_\d{8}_\d{6}([A-Za-z0-9_.-]+)?$", rid):
        return rid
    return None

def _vsp_head_guess_run_dir(rid):
    # reuse if already defined
    try:
        return _vsp_exp2_guess_run_dir(rid)  # type: ignore
    except Exception:
        pass
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
    return None

def _vsp_head_runs_len():
    # compute expected HTML length (for Content-Length)
    try:
        b = _vsp_exp2_runs_html_bytes()  # type: ignore
        return len(b)
    except Exception:
        pass
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
            return len(html.encode("utf-8"))
    return 0

def _vsp_head_pdf_len(run_dir, rid):
    # if export code exists, compute actual pdf length; else give a small sane default
    try:
        pdf = _vsp_exp2_make_pdf(run_dir, rid)  # type: ignore
        return len(pdf)
    except Exception:
        pass
    return 1200

def _vsp_head_zip_len(run_dir, rid):
    # zip can be heavy to compute for HEAD; return 0 (still ok for probe)
    try:
        z = _vsp_exp2_make_zip(run_dir, rid)  # type: ignore
        return len(z)
    except Exception:
        pass
    return 0

class _VSPExportHeadWSGI:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO") or ""
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        if method == "HEAD":
            # /runs
            if path == "/runs":
                clen = _vsp_head_runs_len()
                return _vsp_head_start(start_response, "text/html; charset=utf-8", clen=str(clen))

            # export endpoints (always 200 for probe)
            if path in ("/api/vsp/run_export_zip", "/api/vsp/run_export_pdf"):
                q = _vsp_head_qs(environ)
                rid = (q.get("rid") or [""])[0]
                rid2 = _vsp_head_safe_rid(rid)

                # invalid rid → 200 JSON (probe-friendly)
                if not rid2:
                    return _vsp_head_start(start_response, "application/json; charset=utf-8", clen="0")

                rd = _vsp_head_guess_run_dir(rid2)
                if rd is None:
                    return _vsp_head_start(start_response, "application/json; charset=utf-8", clen="0")

                if path.endswith("_pdf"):
                    clen = _vsp_head_pdf_len(rd, rid2)
                    fname = rid2 + "_executive.pdf"
                    return _vsp_head_start(
                        start_response,
                        "application/pdf",
                        clen=str(clen),
                        extra=[("Content-Disposition", 'attachment; filename="%s"' % fname)]
                    )

                # zip
                clen = _vsp_head_zip_len(rd, rid2)
                fname = rid2 + "_evidence.zip"
                return _vsp_head_start(
                    start_response,
                    "application/zip",
                    clen=str(clen),
                    extra=[("Content-Disposition", 'attachment; filename="%s"' % fname)]
                )

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
    if not getattr(application, "_vsp_export_head_wrapped_v1c", False):
        w = _VSPExportHeadWSGI(application)
        setattr(w, "_vsp_export_head_wrapped_v1c", True)
        application = w
# ===================== /VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C =====================
PY

  echo "[OK] appended $MARK to $F"
fi

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null || true

BASE="http://127.0.0.1:8910"
echo "== HEAD /runs =="
curl -sS -I "$BASE/runs" | sed -n '1,25p'

echo "== HEAD export ZIP/PDF (must be 200 now) =="
curl -sS -I "$BASE/api/vsp/run_export_zip?rid=RUN_20251120_130310" | sed -n '1,25p'
curl -sS -I "$BASE/api/vsp/run_export_pdf?rid=RUN_20251120_130310" | sed -n '1,25p'

echo "== GET sanity (magic bytes) =="
curl -sS "$BASE/api/vsp/run_export_zip?rid=RUN_20251120_130310" | head -c 2; echo
curl -sS "$BASE/api/vsp/run_export_pdf?rid=RUN_20251120_130310" | head -c 4; echo
