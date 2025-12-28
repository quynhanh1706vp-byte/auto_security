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
MARK="VSP_P1_AUDIT_PACK_MANIFEST_API_V3_FSSEARCH_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_before_manifestv3_${TS}"
echo "[SNAPSHOT] ${W}.bak_before_manifestv3_${TS}"

echo "== [1] recover: find latest compiling backup =="
GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile

baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)
for b in baks[:220]:
    try:
        py_compile.compile(str(b), doraise=True)
        print(str(b))
        raise SystemExit(0)
    except Exception:
        continue
raise SystemExit(1)
PY
)"
[ -n "${GOOD:-}" ] || { echo "[ERR] no compiling backup found"; ls -1t wsgi_vsp_ui_gateway.py.bak_* | head -n 20 || true; exit 2; }
echo "[OK] GOOD=$GOOD"
cp -f "$GOOD" "$W"
python3 -m py_compile "$W"
echo "[OK] restored + py_compile passed"

echo "== [2] append Manifest V3 (FS-search, bounded) at EOF =="
python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
mark="VSP_P1_AUDIT_PACK_MANIFEST_API_V3_FSSEARCH_V1"
if mark in s:
    print("[SKIP] V3 already present")
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_AUDIT_PACK_MANIFEST_API_V3_FSSEARCH_V1 =====================
# API: /api/vsp/audit_pack_manifest?rid=<RID>&lite=1(optional)
# V3: find RID dir by bounded FS-search (no dependency on run_file_allow/internal proxy).
#      Never breaks import: whole block is guarded.
try:
    import json, time, traceback, os
    from pathlib import Path
    from urllib.parse import parse_qs

    _VSP_MF_ITEMS_BASE_V3 = [
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
    _VSP_MF_FULL_ONLY_V3 = ["findings_unified.json"]

    # Candidate roots (fast checks first). You can add more safely.
    _VSP_MF_ROOTS_V3 = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1",
        "/home/test/Data",  # last resort (bounded walk)
    ]

    def _vsp_safe_join_v3(run_dir: Path, rel: str) -> Path:
        rel = (rel or "").lstrip("/").replace("\\", "/")
        parts = [x for x in rel.split("/") if x not in ("", ".", "..")]
        return run_dir.joinpath(*parts)

    def _vsp_find_rid_dir_v3(rid: str) -> Path | None:
        # 1) direct hit root/rid
        for root in _VSP_MF_ROOTS_V3:
            try:
                d = Path(root) / rid
                if d.is_dir():
                    return d
            except Exception:
                pass

        # 2) bounded search: depth<=3, dirs<=3500
        #    Stops on first match of a directory named exactly RID.
        max_depth = 3
        max_dirs = 3500
        scanned = 0

        for root in _VSP_MF_ROOTS_V3:
            rr = Path(root)
            if not rr.is_dir():
                continue
            root_depth = len(rr.parts)
            try:
                for cur, dirnames, _filenames in os.walk(str(rr), topdown=True):
                    scanned += 1
                    if scanned > max_dirs:
                        return None
                    curp = Path(cur)
                    depth = len(curp.parts) - root_depth
                    if depth > max_depth:
                        dirnames[:] = []
                        continue
                    # prune common heavy dirs
                    dirnames[:] = [d for d in dirnames if d not in (".git","node_modules","__pycache__","venv",".venv")]
                    # check children quickly
                    if rid in dirnames:
                        cand = curp / rid
                        if cand.is_dir():
                            return cand
            except Exception:
                continue
        return None

    def _vsp_manifest_v3(inner):
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

                run_dir = _vsp_find_rid_dir_v3(rid)
                if not run_dir:
                    b = json.dumps({"ok": False, "err": "rid not found", "rid": rid}, ensure_ascii=False).encode("utf-8")
                    start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                    return [b]

                items = list(_VSP_MF_ITEMS_BASE_V3)
                if not lite:
                    items = _VSP_MF_FULL_ONLY_V3 + items

                included=[]; missing=[]
                for rel in items:
                    fp = _vsp_safe_join_v3(run_dir, rel)
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
        application = _vsp_manifest_v3(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _vsp_manifest_v3(app)

    print("[VSP] manifest V3 FSSEARCH enabled")
except Exception as _e:
    print("[VSP] manifest V3 FSSEARCH ERROR:", _e)
# ===================== /VSP_P1_AUDIT_PACK_MANIFEST_API_V3_FSSEARCH_V1 =====================
""").strip("\n")

p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended manifest V3 FSSEARCH")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile passed after V3 append"

systemctl restart "$SVC" 2>/dev/null || true

echo "== [3] smoke manifest (lite) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"inc=",j.get("included_count"),"miss=",j.get("missing_count"),"err=",j.get("errors_count"),"run_dir=",j.get("run_dir"))'
echo "[DONE]"
