#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK2="VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_manifestv2_${TS}"
echo "[BACKUP] ${W}.bak_manifestv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS" in s:
    print("[SKIP] V2 already present")
    raise SystemExit(0)

start = "# ===================== VSP_P1_AUDIT_PACK_MANIFEST_API_V1"
end   = "# ===================== /VSP_P1_AUDIT_PACK_MANIFEST_API_V1"
i = s.find(start)
j = s.find(end)
if i < 0 or j < 0 or j < i:
    print("[ERR] cannot find MANIFEST_API_V1 block markers to replace")
    raise SystemExit(2)

v2 = textwrap.dedent(r"""
# ===================== VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS =====================
# API: /api/vsp/audit_pack_manifest?rid=<RID>&lite=1(optional)
# FS-check (no internal run_file_allow calls) => errors_count should be 0 unless RID not found.
try:
    import json, time, traceback, os
    from pathlib import Path
    from urllib.parse import parse_qs

    _VSP_MANIFEST_ALLOWED = [
        "run_gate_summary.json",
        "run_gate.json",
        "SUMMARY.txt",
        "run_manifest.json",
        "run_evidence_index.json",
        "reports/findings_unified.csv",
        "reports/findings_unified.sarif",
        "reports/findings_unified.html",
        "reports/findings_unified.pdf",
    ]
    _VSP_MANIFEST_FULL_ONLY = ["findings_unified.json"]

    _VSP_RUN_ROOTS = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]

    def _vsp_find_run_dir(rid: str) -> Path | None:
        for root in _VSP_RUN_ROOTS:
            try:
                cand = Path(root) / rid
                if cand.is_dir():
                    return cand
            except Exception:
                pass
        return None

    def _vsp_safe_join(run_dir: Path, rel: str) -> Path:
        # prevent traversal
        rel = (rel or "").lstrip("/").replace("\\", "/")
        parts = [p for p in rel.split("/") if p not in ("", ".", "..")]
        return run_dir.joinpath(*parts)

    def _wrap_audit_manifest_v2(inner):
        def _wsgi(environ, start_response):
            if (environ.get("PATH_INFO","") or "") != "/api/vsp/audit_pack_manifest":
                return inner(environ, start_response)
            try:
                qs = parse_qs(environ.get("QUERY_STRING","") or "")
                rid = (qs.get("rid") or [""])[0].strip()
                lite = (qs.get("lite") or [""])[0].strip() in ("1","true","yes","on")

                if not rid:
                    b = json.dumps({"ok":False,"err":"missing rid"}, ensure_ascii=False).encode("utf-8")
                    start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                    return [b]

                run_dir = _vsp_find_run_dir(rid)
                if not run_dir:
                    b = json.dumps({"ok":False,"err":"rid not found","rid":rid}, ensure_ascii=False).encode("utf-8")
                    start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                    return [b]

                items = list(_VSP_MANIFEST_ALLOWED)
                if not lite:
                    items = _VSP_MANIFEST_FULL_ONLY + items

                included=[]; missing=[]
                for rel in items:
                    fp = _vsp_safe_join(run_dir, rel)
                    if fp.is_file():
                        try:
                            included.append({"path": rel, "bytes": fp.stat().st_size})
                        except Exception:
                            included.append({"path": rel, "bytes": None})
                    else:
                        missing.append({"path": rel, "reason": "not found"})

                out = {
                    "ok": True, "rid": rid, "lite": lite,
                    "run_dir": str(run_dir),
                    "included_count": len(included),
                    "missing_count": len(missing),
                    "errors_count": 0,
                    "included": included,
                    "missing": missing,
                    "errors": [],
                    "ts": int(time.time()),
                }
                b = json.dumps(out, ensure_ascii=False).encode("utf-8")
                start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                return [b]
            except Exception as e:
                b = json.dumps({"ok":False,"err":str(e),"tb":traceback.format_exc(limit=6)}, ensure_ascii=False).encode("utf-8")
                start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                return [b]
        return _wsgi

    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_audit_manifest_v2(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_audit_manifest_v2(app)

    print("[VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS] enabled")
except Exception as _e:
    print("[VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS] ERROR:", _e)
# ===================== /VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS =====================
""").strip("\n")

# replace whole V1 block
s2 = s[:i] + v2 + "\n" + s[j+len(end):]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced manifest API V1 -> V2 FS-check")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke manifest (lite) after V2 =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"inc=",j.get("included_count"),"miss=",j.get("missing_count"),"err=",j.get("errors_count"),"run_dir=",j.get("run_dir"))'

echo "[DONE]"
