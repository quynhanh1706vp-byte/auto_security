#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fixc_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl; need awk; need head
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl" | tee -a "$OUT/log.txt"; exit 2; }

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$W" "$OUT/${W}.bak_${TS}"
echo "[OK] backup => $OUT/${W}.bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import sys, re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P463FIXC_EXPORTS_WSGI_MW_V1"
if MARK in s:
    print("[OK] already patched P463fixc")
    sys.exit(0)

block = r'''
# --- VSP_P463FIXC_EXPORTS_WSGI_MW_V1 ---
def _vsp_p463fixc_install_exports_wsgi_mw():
    """
    Install a WSGI middleware to serve:
      /api/vsp/export_csv
      /api/vsp/export_tgz
      /api/vsp/sha256
    Works even when there's NO real Flask app (pure WSGI wrapper mode).
    Never crash boot.
    """
    try:
        import os, time, json, tarfile, hashlib
        from pathlib import Path
        from urllib.parse import parse_qs

        roots = [
            Path("/home/test/Data/SECURITY_BUNDLE"),
            Path("/home/test/Data/SECURITY_BUNDLE/out"),
            Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
            Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
            Path(__file__).resolve().parent / "out_ci",
        ]
        roots = [r for r in roots if r.exists()]

        cache_dir = (Path(__file__).resolve().parent / "out_ci" / "exports_cache")
        cache_dir.mkdir(parents=True, exist_ok=True)

        _latest_cache = {"rid": None, "ts": 0.0}
        def _latest_rid():
            now=time.time()
            if _latest_cache["rid"] and (now - _latest_cache["ts"] < 2.0):
                return _latest_cache["rid"]

            best=None
            # bounded scan
            scan_roots = ["/home/test/Data/SECURITY_BUNDLE", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]
            for root in scan_roots:
                if not os.path.isdir(root):
                    continue
                for dirpath, dirnames, _ in os.walk(root):
                    if "/.venv/" in dirpath or "/venv/" in dirpath or "/node_modules/" in dirpath:
                        dirnames[:] = []
                        continue
                    for dn in dirnames:
                        if dn.startswith("VSP_CI_"):
                            if best is None or dn > best:
                                best = dn
                    # prune depth
                    if dirpath.count(os.sep) - root.count(os.sep) > 6:
                        dirnames[:] = []
            _latest_cache["rid"]=best
            _latest_cache["ts"]=now
            return best

        def _find_run_dir(rid: str):
            if not rid:
                return None
            rid=str(rid).strip()
            for base in roots:
                try:
                    for d in base.rglob(rid):
                        if d.is_dir() and d.name == rid:
                            return d
                except Exception:
                    pass
            return None

        def _pick_csv(run_dir: Path):
            for f in (run_dir/"reports"/"findings_unified.csv", run_dir/"report"/"findings_unified.csv", run_dir/"findings_unified.csv"):
                try:
                    if f.is_file() and f.stat().st_size > 0:
                        return f
                except Exception:
                    pass
            return None

        def _build_tgz(run_dir: Path, rid: str):
            rid=str(rid).strip() or "RID_UNKNOWN"
            out = cache_dir / f"export_{rid}.tgz"
            if out.is_file() and out.stat().st_size > 0:
                return out

            tmp = cache_dir / f".tmp_export_{rid}.{os.getpid()}.tgz"
            include = [
                "SUMMARY.txt",
                "run_manifest.json",
                "run_evidence_index.json",
                "verdict_4t.json",
                "run_gate.json",
                "reports/run_gate_summary.json",
                "reports/findings_unified.json",
                "reports/findings_unified.csv",
                "reports/findings_unified.sarif",
                "findings_unified.json",
                "findings_unified.csv",
                "findings_unified.sarif",
                "reports",
            ]
            with tarfile.open(tmp, "w:gz") as tf:
                for rel in include:
                    pth = run_dir/rel
                    if not pth.exists():
                        continue
                    if pth.is_dir():
                        for sub in pth.rglob("*"):
                            if sub.is_file():
                                tf.add(str(sub), arcname=f"{rid}/{sub.relative_to(run_dir)}", recursive=False)
                    else:
                        tf.add(str(pth), arcname=f"{rid}/{pth.relative_to(run_dir)}", recursive=False)

            if not tmp.is_file() or tmp.stat().st_size == 0:
                try: tmp.unlink(missing_ok=True)
                except Exception: pass
                return None
            tmp.replace(out)
            return out

        def _sha256(path: Path):
            h=hashlib.sha256()
            with open(path,"rb") as f:
                for chunk in iter(lambda:f.read(1024*1024), b""):
                    h.update(chunk)
            return h.hexdigest()

        def _json(start_response, code: str, obj: dict):
            body=(json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")
            start_response(code, [
                ("Content-Type","application/json; charset=utf-8"),
                ("Content-Length", str(len(body))),
                ("Cache-Control","no-store"),
                ("X-VSP-P463FIXC", "1"),
            ])
            return [body]

        def _send_file(environ, start_response, path: Path, ctype: str, filename: str):
            try:
                st = path.stat()
                start_response("200 OK", [
                    ("Content-Type", ctype),
                    ("Content-Length", str(st.st_size)),
                    ("Content-Disposition", f'attachment; filename="{filename}"'),
                    ("Cache-Control","no-store"),
                    ("X-VSP-P463FIXC","1"),
                ])
                # efficient wrapper if available
                w = environ.get("wsgi.file_wrapper")
                if w:
                    return w(open(path, "rb"), 1024*1024)
                # fallback streaming
                def gen():
                    with open(path, "rb") as f:
                        while True:
                            b = f.read(1024*1024)
                            if not b:
                                break
                            yield b
                return gen()
            except Exception as e:
                return _json(start_response, "500 INTERNAL SERVER ERROR", {"ok":0, "err":"send_file_failed", "detail":str(e)})

        class _VSPExportsWSGIMW:
            def __init__(self, app):
                self.app = app
            def __call__(self, environ, start_response):
                try:
                    path = environ.get("PATH_INFO","") or ""
                    method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
                    if method != "GET":
                        return self.app(environ, start_response)

                    if path in ("/api/vsp/export_csv", "/api/vsp/export_tgz", "/api/vsp/sha256"):
                        qs = parse_qs(environ.get("QUERY_STRING","") or "", keep_blank_values=True)
                        rid = (qs.get("rid", [""])[0] or "").strip()
                        if not rid:
                            rid = _latest_rid() or ""

                        if not rid:
                            return _json(start_response, "400 BAD REQUEST", {"ok":0, "err":"no rid (auto latest failed)"})

                        run_dir = _find_run_dir(rid)
                        if not run_dir:
                            return _json(start_response, "404 NOT FOUND", {"ok":0, "err":"rid not found", "rid":rid})

                        if path == "/api/vsp/export_csv":
                            f = _pick_csv(run_dir)
                            if not f:
                                return _json(start_response, "404 NOT FOUND", {"ok":0, "err":"findings_unified.csv not found", "rid":rid, "run_dir":str(run_dir)})
                            return _send_file(environ, start_response, f, "text/csv", f"findings_unified_{rid}.csv")

                        if path == "/api/vsp/export_tgz":
                            tgz = _build_tgz(run_dir, rid)
                            if not tgz:
                                return _json(start_response, "500 INTERNAL SERVER ERROR", {"ok":0, "err":"failed to build tgz", "rid":rid})
                            return _send_file(environ, start_response, tgz, "application/gzip", f"vsp_export_{rid}.tgz")

                        if path == "/api/vsp/sha256":
                            tgz = _build_tgz(run_dir, rid)
                            if not tgz:
                                return _json(start_response, "500 INTERNAL SERVER ERROR", {"ok":0, "err":"failed to build tgz", "rid":rid})
                            return _json(start_response, "200 OK", {"ok":1, "rid":rid, "file":tgz.name, "bytes":tgz.stat().st_size, "sha256":_sha256(tgz)})

                    return self.app(environ, start_response)
                except Exception:
                    # never break main app
                    return self.app(environ, start_response)

        # wrap both 'application' and 'app' if present
        for k in ("application", "app"):
            if k in globals():
                try:
                    v = globals()[k]
                    if not getattr(v, "_vsp_p463fixc_wrapped", False):
                        w = _VSPExportsWSGIMW(v)
                        setattr(w, "_vsp_p463fixc_wrapped", True)
                        globals()[k] = w
                except Exception:
                    pass

        return True
    except Exception:
        return False

_vsp_p463fixc_install_exports_wsgi_mw()
# --- /VSP_P463FIXC_EXPORTS_WSGI_MW_V1 ---
'''

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended P463fixc WSGI MW")
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

echo "== TEST sha256 ==" | tee -a "$OUT/log.txt"
curl -sS --connect-timeout 1 --max-time 10 "$BASE/api/vsp/sha256" | head -c 240 | tee -a "$OUT/log.txt"
echo "" | tee -a "$OUT/log.txt"

echo "== TEST export_csv headers ==" | tee -a "$OUT/log.txt"
curl -sS -D- -o /dev/null --connect-timeout 1 --max-time 10 "$BASE/api/vsp/export_csv" \
 | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:/{print}' | tee -a "$OUT/log.txt"

echo "== TEST export_tgz headers ==" | tee -a "$OUT/log.txt"
curl -sS -D- -o /dev/null --connect-timeout 1 --max-time 10 "$BASE/api/vsp/export_tgz" \
 | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:/{print}' | tee -a "$OUT/log.txt"

echo "[OK] DONE: $OUT/log.txt" | tee -a "$OUT/log.txt"
