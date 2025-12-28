#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_wsgi_export_${TS}"
echo "[BACKUP] ${WSGI}.bak_wsgi_export_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_WSGI_INTERCEPT_RUN_EXPORT_V4"
if MARK in s:
    print("[OK] marker exists; skip")
else:
    blk = textwrap.dedent(r"""
    # ===================== VSP_P1_WSGI_INTERCEPT_RUN_EXPORT_V4 =====================
    # Intercept /api/vsp/run_export_v3 at WSGI layer to bypass proxy/dispatcher route ambiguity.
    try:
        import os, re, json, tarfile
        from pathlib import Path as _Path
        from urllib.parse import parse_qs as _parse_qs

        def _vsp__rid_norm_v4(rid0: str) -> str:
            rid0 = (rid0 or "").strip()
            m = re.search(r'(\d{8}_\d{6})', rid0)
            if m:
                return m.group(1)
            return rid0.replace("VSP_CI_RUN_","").replace("VSP_CI_","").replace("RUN_","").strip()

        def _vsp__resolve_run_dir_v4(rid0: str, rid_norm: str) -> str:
            # strongest: the path you already confirmed exists
            cand = _Path("/home/test/Data/SECURITY_BUNDLE/out") / (rid0 if rid0.startswith("RUN_") else f"RUN_{rid_norm}")
            if cand.exists() and cand.is_dir():
                return str(cand)

            ui_root = _Path(__file__).resolve().parent
            bundle_root = ui_root.parent
            roots = [
                ui_root/"out_ci", ui_root/"out",
                bundle_root/"out_ci", bundle_root/"out",
                _Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
            ]

            names = []
            for x in [rid0, rid_norm]:
                if x and x not in names:
                    names.append(x)
            if rid_norm:
                for pref in ["RUN_","VSP_CI_RUN_","VSP_CI_"]:
                    n = pref + rid_norm
                    if n not in names:
                        names.append(n)

            for root in roots:
                try:
                    if not root.exists(): 
                        continue
                    for nm in names:
                        c = root / nm
                        if c.exists() and c.is_dir():
                            return str(c)
                except Exception:
                    pass
            return ""

        def _vsp__wsgi_json(start_response, code: str, payload: dict):
            body = (json.dumps(payload, ensure_ascii=False)).encode("utf-8")
            hdrs = [
                ("Content-Type","application/json; charset=utf-8"),
                ("Content-Length", str(len(body))),
                ("X-VSP-HOTFIX","wsgi_export_v4"),
            ]
            start_response(code, hdrs)
            return [body]

        def _vsp__tgz_build_v4(run_dir: str, rid_norm: str) -> str:
            rd = _Path(run_dir)
            out = _Path("/tmp") / f"vsp_export_{rid_norm or rd.name}.tgz"
            try:
                if out.exists(): out.unlink()
            except Exception:
                pass

            picks = [
                rd/"run_gate.json",
                rd/"run_gate_summary.json",
                rd/"findings_unified.json",
                rd/"reports",
                rd/"SUMMARY.txt",
            ]
            with tarfile.open(out, "w:gz") as tf:
                base = f"{rid_norm or rd.name}"
                for x in picks:
                    try:
                        if not x.exists(): 
                            continue
                        tf.add(str(x), arcname=f"{base}/{x.name}")
                    except Exception:
                        continue
            return str(out)

        def _vsp__wsgi_send_file(start_response, fp: str, dl_name: str, ctype: str):
            fsz = 0
            try:
                fsz = os.path.getsize(fp)
            except Exception:
                fsz = 0
            hdrs = [
                ("Content-Type", ctype),
                ("Content-Disposition", f'attachment; filename="{dl_name}"'),
                ("Content-Length", str(fsz)),
                ("X-VSP-HOTFIX","wsgi_export_v4"),
            ]
            start_response("200 OK", hdrs)

            file_wrapper = None
            try:
                # wsgi.file_wrapper may exist in environ but not here; fallback to chunk iterator
                file_wrapper = None
            except Exception:
                file_wrapper = None

            def _iterfile():
                with open(fp, "rb") as f:
                    while True:
                        b = f.read(1024*256)
                        if not b:
                            break
                        yield b
            return _iterfile()

        def _vsp_wsgi_export_intercept_v4(app_callable):
            def _wrap(environ, start_response):
                try:
                    path = (environ.get("PATH_INFO") or "").strip()
                    if path != "/api/vsp/run_export_v3":
                        return app_callable(environ, start_response)

                    qs = _parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)
                    rid0 = (qs.get("rid",[""])[0] or qs.get("run_id",[""])[0] or "").strip()
                    fmt = (qs.get("fmt",["tgz"])[0] or "tgz").strip().lower()
                    rid_norm = _vsp__rid_norm_v4(rid0)

                    run_dir = _vsp__resolve_run_dir_v4(rid0, rid_norm)
                    if not run_dir:
                        return _vsp__wsgi_json(start_response, "404 NOT FOUND", {
                            "ok": False, "error":"RUN_DIR_NOT_FOUND", "rid": rid0, "rid_norm": rid_norm, "hotfix":"wsgi_export_v4"
                        })

                    if fmt == "tgz":
                        fp = _vsp__tgz_build_v4(run_dir, rid_norm or rid0)
                        dl = f"VSP_EXPORT_{rid_norm or rid0}.tgz"
                        return _vsp__wsgi_send_file(start_response, fp, dl, "application/gzip")

                    # csv/html: best-effort direct file
                    rd = _Path(run_dir)
                    if fmt == "csv":
                        cand = rd/"reports"/"findings_unified.csv"
                        if not cand.exists(): cand = rd/"reports"/"findings.csv"
                        if not cand.exists():
                            return _vsp__wsgi_json(start_response, "404 NOT FOUND", {"ok":False,"error":"CSV_NOT_FOUND","rid":rid0,"rid_norm":rid_norm,"hotfix":"wsgi_export_v4"})
                        return _vsp__wsgi_send_file(start_response, str(cand), f"VSP_EXPORT_{rid_norm or rid0}.csv", "text/csv")

                    if fmt == "html":
                        cand = rd/"reports"/"findings_unified.html"
                        if not cand.exists(): cand = rd/"reports"/"index.html"
                        if not cand.exists():
                            return _vsp__wsgi_json(start_response, "404 NOT FOUND", {"ok":False,"error":"HTML_NOT_FOUND","rid":rid0,"rid_norm":rid_norm,"hotfix":"wsgi_export_v4"})
                        return _vsp__wsgi_send_file(start_response, str(cand), f"VSP_EXPORT_{rid_norm or rid0}.html", "text/html")

                    return _vsp__wsgi_json(start_response, "400 BAD REQUEST", {"ok":False,"error":"FMT_UNSUPPORTED","fmt":fmt,"hotfix":"wsgi_export_v4"})
                except Exception as e:
                    return _vsp__wsgi_json(start_response, "500 INTERNAL SERVER ERROR", {"ok":False,"error":"HOTFIX_EXCEPTION","msg":str(e),"hotfix":"wsgi_export_v4"})
            return _wrap

        # wrap both 'application' and 'app' if present
        _orig = globals().get("application") or globals().get("app")
        if callable(_orig):
            _wrapped = _vsp_wsgi_export_intercept_v4(_orig)
            if "application" in globals(): globals()["application"] = _wrapped
            if "app" in globals(): globals()["app"] = _wrapped
    except Exception:
        pass
    # ===================== /VSP_P1_WSGI_INTERCEPT_RUN_EXPORT_V4 =====================
    """).rstrip() + "\n"

    p.write_text(s.rstrip() + "\n\n" + blk, encoding="utf-8")
    print("[OK] appended WSGI intercept block V4")

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK:", p)
PY

systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== test export TGZ (should be 200 OR JSON with hotfix=wsgi_export_v4) =="
RID="RUN_20251120_130310"
curl -sS -L -D /tmp/vsp_exp_hdr.txt -o /tmp/vsp_exp_body.bin \
  "$BASE/api/vsp/run_export_v3?rid=$RID&fmt=tgz" \
  -w "\nHTTP=%{http_code}\n"
echo "X-VSP-HOTFIX:"
grep -i '^X-VSP-HOTFIX:' /tmp/vsp_exp_hdr.txt || true
echo "Content-Disposition:"
grep -i '^Content-Disposition:' /tmp/vsp_exp_hdr.txt || true
echo "BODY_HEAD:"
head -c 120 /tmp/vsp_exp_body.bin; echo
