#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_preempt_exportpdf_${TS}"
echo "[BACKUP] $F.bak_preempt_exportpdf_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WSGI_PREEMPT_V1_EXPORTPDF_PATCH_V1 ==="
if TAG in t:
    print("[OK] already patched, skip")
    raise SystemExit(0)

needle_tag = "VSP_WSGI_PREEMPT_V1"
i = t.find(needle_tag)
if i < 0:
    raise SystemExit("[ERR] cannot find VSP_WSGI_PREEMPT_V1 marker in file")

# find a stable insertion point inside the preempt __call__ path parsing area
# try to inject right after the first PATH_INFO read after the marker
j = t.find("PATH_INFO", i)
if j < 0:
    raise SystemExit("[ERR] cannot find PATH_INFO usage after VSP_WSGI_PREEMPT_V1 marker")

# insert after the line containing PATH_INFO (end of that line)
line_end = t.find("\n", j)
if line_end < 0:
    raise SystemExit("[ERR] unexpected EOF near PATH_INFO line")

patch = f"""
{TAG}
        # --- export pdf preempt (commercial) ---
        try:
            from urllib.parse import parse_qs
            _path = environ.get("PATH_INFO", "") or ""
            if _path.startswith("/api/vsp/run_export_v3/"):
                _qs = environ.get("QUERY_STRING", "") or ""
                _q = parse_qs(_qs)
                _fmt = (_q.get("fmt", ["html"])[0] or "html").lower().strip()
                if _fmt == "pdf":
                    import os, glob, json as _json
                    _rid = _path.split("/api/vsp/run_export_v3/", 1)[1].strip("/")
                    _rid_norm = _rid[4:] if _rid.startswith("RUN_") else _rid
                    _base = os.environ.get("VSP_CI_OUT_ROOT") or "/home/test/Data/SECURITY-10-10-v4/out_ci"
                    _ci = os.path.join(_base, _rid_norm)
                    if not os.path.isdir(_ci):
                        _ci2 = ""
                        for _d in sorted(glob.glob(os.path.join(_base, "VSP_CI_*")), reverse=True):
                            if _rid_norm in os.path.basename(_d):
                                _ci2 = _d
                                break
                        _ci = _ci2 or ""

                    _pdf = ""
                    _best = -1.0
                    if _ci:
                        for _pat in (os.path.join(_ci, "reports", "*.pdf"), os.path.join(_ci, "*.pdf")):
                            for _f in glob.glob(_pat):
                                try:
                                    _m = os.path.getmtime(_f)
                                except Exception:
                                    continue
                                if _m > _best:
                                    _best = _m
                                    _pdf = _f

                    if _pdf and os.path.isfile(_pdf):
                        _sz = os.path.getsize(_pdf)
                        start_response("200 OK", [
                            ("Content-Type", "application/pdf"),
                            ("Content-Disposition", f'attachment; filename="{{os.path.basename(_pdf)}}"'),
                            ("Content-Length", str(_sz)),
                            ("X-VSP-EXPORT-AVAILABLE", "1"),
                            ("X-VSP-EXPORT-FILE", os.path.basename(_pdf)),
                        ])
                        return open(_pdf, "rb")

                    _body = _json.dumps({{
                        "ok": False, "http_code": 404, "error": "PDF_NOT_FOUND",
                        "rid": _rid, "rid_norm": _rid_norm, "ci_run_dir": _ci or None
                    }}).encode("utf-8")
                    start_response("404 NOT FOUND", [
                        ("Content-Type", "application/json"),
                        ("Content-Length", str(len(_body))),
                        ("X-VSP-EXPORT-AVAILABLE", "0"),
                    ])
                    return [_body]
        except Exception:
            pass
        # --- end export pdf preempt ---
"""

t2 = t[:line_end+1] + patch + t[line_end+1:]
p.write_text(t2, encoding="utf-8")
print("[OK] injected exportpdf handler into PREEMPT_V1")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
