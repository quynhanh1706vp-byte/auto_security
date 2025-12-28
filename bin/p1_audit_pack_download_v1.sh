#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v tar >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_AUDIT_PACK_DOWNLOAD_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_auditpack_${TS}"
echo "[BACKUP] ${W}.bak_auditpack_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_P1_AUDIT_PACK_DOWNLOAD_V1" in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

anchor = "# ===================== VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C ====================="
idx = s.find(anchor)
if idx < 0: idx = len(s)

patch = textwrap.dedent(r"""
# ===================== VSP_P1_AUDIT_PACK_DOWNLOAD_V1 =====================
# API: /api/vsp/audit_pack_download?rid=<RID>
# Build tgz on the fly from allowed run dir; never 500 (returns JSON error 200).
try:
    import os, io, tarfile, json, time, re
    from pathlib import Path
    from urllib.parse import parse_qs

    _RID_OK = re.compile(r'^[A-Za-z0-9_.-]+$')
    _RUN_ROOTS = [
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
    ]

    def _json200(start_response, obj):
        b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        start_response("200 OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(b))),
        ])
        return [b]

    def _find_run_dir(rid:str):
        for root in _RUN_ROOTS:
            d = root / rid
            if d.is_dir():
                return d
        return None

    def _tar_add(tf, base:Path, relpath:Path):
        ap = base / relpath
        if ap.is_file() and ap.stat().st_size > 0:
            tf.add(str(ap), arcname=str(relpath))

    def _wrap_audit_pack(inner):
        def _wsgi(environ, start_response):
            if (environ.get("PATH_INFO","") or "") != "/api/vsp/audit_pack_download":
                return inner(environ, start_response)
            try:
                qs = parse_qs(environ.get("QUERY_STRING","") or "")
                rid = (qs.get("rid") or [""])[0]
                if not rid or not _RID_OK.match(rid):
                    return _json200(start_response, {"ok": False, "err": "bad rid"})
                d = _find_run_dir(rid)
                if not d:
                    return _json200(start_response, {"ok": False, "err": "rid not found", "rid": rid})

                # Build tgz in memory (small enough usually). If huge later, we can stream.
                bio = io.BytesIO()
                with tarfile.open(fileobj=bio, mode="w:gz") as tf:
                    # Core evidence files
                    cands = [
                        Path("run_gate_summary.json"),
                        Path("run_gate.json"),
                        Path("findings_unified.json"),
                        Path("reports/findings_unified.csv"),
                        Path("reports/findings_unified.sarif"),
                        Path("SUMMARY.txt"),
                        Path("run_manifest.json"),
                        Path("run_evidence_index.json"),
                    ]
                    for r in cands:
                        _tar_add(tf, d, r)

                    # include reports folder (html/pdf) best effort
                    rep = d / "reports"
                    if rep.is_dir():
                        for ap in rep.rglob("*"):
                            if ap.is_file() and ap.stat().st_size > 0:
                                # keep only common report types
                                if ap.suffix.lower() in (".html",".pdf",".csv",".sarif",".json",".txt",".md"):
                                    rel = ap.relative_to(d)
                                    tf.add(str(ap), arcname=str(rel))

                data = bio.getvalue()
                name = f"audit_pack_{rid}.tgz"
                start_response("200 OK", [
                    ("Content-Type","application/gzip"),
                    ("Content-Disposition", f'attachment; filename="{name}"'),
                    ("Cache-Control","no-store"),
                    ("X-VSP-AUDIT-PACK", "1"),
                    ("Content-Length", str(len(data))),
                ])
                return [data]
            except Exception as e:
                return _json200(start_response, {"ok": False, "err": str(e)})
        return _wsgi

    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_audit_pack(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_audit_pack(app)

    print("[VSP_P1_AUDIT_PACK_DOWNLOAD_V1] enabled")
except Exception as _e:
    print("[VSP_P1_AUDIT_PACK_DOWNLOAD_V1] ERROR:", _e)
# ===================== /VSP_P1_AUDIT_PACK_DOWNLOAD_V1 =====================
""")

p.write_text(s[:idx] + patch + "\n" + s[idx:], encoding="utf-8")
print("[OK] patched audit pack api")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: pick rid from /api/vsp/runs?limit=1 then HEAD audit pack =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); 
r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")' )"
echo "[RID]=$RID"
if [ -n "$RID" ]; then
  curl -sS -I "$BASE/api/vsp/audit_pack_download?rid=$RID" | egrep -i 'HTTP/|content-disposition|x-vsp-audit-pack|content-length' || true
else
  echo "[WARN] cannot resolve RID from runs api"
fi
echo "[DONE]"
