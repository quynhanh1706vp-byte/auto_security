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
MARK="VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS_APPEND_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_broken_before_recover_${TS}"
echo "[SNAPSHOT] ${W}.bak_broken_before_recover_${TS}"

echo "== find latest compiling backup =="
GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)

for b in baks[:120]:
    try:
        py_compile.compile(str(b), doraise=True)
        print(str(b))
        raise SystemExit(0)
    except Exception:
        continue

print("")
raise SystemExit(1)
PY
)"

if [ -z "${GOOD:-}" ]; then
  echo "[ERR] no compiling backup found. Check backups list:"
  ls -1t wsgi_vsp_ui_gateway.py.bak_* | head -n 15 || true
  exit 2
fi

echo "[OK] GOOD=$GOOD"
cp -f "$GOOD" "$W"
python3 -m py_compile "$W"
echo "[OK] restored + py_compile passed"

echo "== append Manifest V2 FS-check wrapper (EOF) =="
python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
mark="VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS_APPEND_V1"
if mark in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS_APPEND_V1 =====================
# FS-check manifest (no run_file_allow internal calls). Outer wrapper intercepts /api/vsp/audit_pack_manifest.
try:
    import json, time, traceback
    from pathlib import Path
    from urllib.parse import parse_qs

    _VSP_MF_ITEMS_BASE = [
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
    _VSP_MF_FULL_ONLY = ["findings_unified.json"]

    _VSP_MF_ROOTS = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]

    def _vsp_mf_find_run_dir(rid: str):
        for root in _VSP_MF_ROOTS:
            try:
                d = Path(root) / rid
                if d.is_dir():
                    return d
            except Exception:
                pass
        return None

    def _vsp_mf_safe_join(run_dir: Path, rel: str) -> Path:
        rel = (rel or "").lstrip("/").replace("\\", "/")
        parts = [x for x in rel.split("/") if x not in ("", ".", "..")]
        return run_dir.joinpath(*parts)

    def _vsp_wrap_manifest_v2_fs(inner):
        def _wsgi(environ, start_response):
            if (environ.get("PATH_INFO","") or "") != "/api/vsp/audit_pack_manifest":
                return inner(environ, start_response)
            try:
                qs = parse_qs(environ.get("QUERY_STRING","") or "")
                rid = (qs.get("rid") or [""])[0].strip()
                lite = (qs.get("lite") or [""])[0].strip() in ("1","true","yes","on")
                if not rid:
                    b = json.dumps({"ok": False, "err": "missing rid"}, ensure_ascii=False).encode("utf-8")
                    start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                    return [b]

                run_dir = _vsp_mf_find_run_dir(rid)
                if not run_dir:
                    b = json.dumps({"ok": False, "err": "rid not found", "rid": rid}, ensure_ascii=False).encode("utf-8")
                    start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                    return [b]

                items = list(_VSP_MF_ITEMS_BASE)
                if not lite:
                    items = _VSP_MF_FULL_ONLY + items

                included = []
                missing = []
                for rel in items:
                    fp = _vsp_mf_safe_join(run_dir, rel)
                    if fp.is_file():
                        try:
                            included.append({"path": rel, "bytes": fp.stat().st_size})
                        except Exception:
                            included.append({"path": rel, "bytes": None})
                    else:
                        missing.append({"path": rel, "reason": "not found"})

                out = {
                    "ok": True,
                    "rid": rid,
                    "lite": lite,
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
                b = json.dumps({"ok": False, "err": str(e), "tb": traceback.format_exc(limit=6)}, ensure_ascii=False).encode("utf-8")
                start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                return [b]
        return _wsgi

    if "application" in globals() and callable(globals().get("application")):
        application = _vsp_wrap_manifest_v2_fs(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _vsp_wrap_manifest_v2_fs(app)

    print("[VSP] manifest v2 fs wrapper enabled")
except Exception as _e:
    print("[VSP] manifest v2 fs wrapper ERROR:", _e)
# ===================== /VSP_P1_AUDIT_PACK_MANIFEST_API_V2_FS_APPEND_V1 =====================
""").strip("\n")

p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended manifest v2 fs wrapper")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile passed after append"

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke manifest (lite) after recover+append =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"inc=",j.get("included_count"),"miss=",j.get("missing_count"),"err=",j.get("errors_count"),"run_dir=",j.get("run_dir"))'

echo "[DONE]"
