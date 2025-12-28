#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
FILES=()
[ -f wsgi_vsp_ui_gateway.py ] && FILES+=(wsgi_vsp_ui_gateway.py)
[ -f vsp_demo_app.py ] && FILES+=(vsp_demo_app.py)
[ -f ui/vsp_demo_app.py ] && FILES+=(ui/vsp_demo_app.py)

[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] no target python files found"; exit 2; }

for F in "${FILES[@]}"; do
  cp -f "$F" "${F}.bak_runfile_v4_${TS}"
  echo "[BACKUP] ${F}.bak_runfile_v4_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import textwrap

marker = "VSP_P1_FORCE_RUN_FILE_HANDLER_V4"

block = textwrap.dedent(r'''
# --- VSP_P1_FORCE_RUN_FILE_HANDLER_V4: force-bind /api/vsp/run_file to whitelist handler (override any "not allowed") ---
def _vsp_p1_force_run_file_handler_v4(app_obj):
    try:
        import os, time, mimetypes
        from pathlib import Path
        from flask import request, jsonify, send_file
    except Exception:
        return False

    if not app_obj or not hasattr(app_obj, "url_map") or not hasattr(app_obj, "view_functions"):
        return False

    BASE_DIRS = [
        os.environ.get("VSP_OUT_DIR", "") or "",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]
    BASE_DIRS = [d for d in BASE_DIRS if d and os.path.isdir(d)]

    DEEP_ROOT = os.environ.get("VSP_DEEP_RUN_ROOT", "/home/test/Data")
    if not os.path.isdir(DEEP_ROOT):
        DEEP_ROOT = ""

    ALLOW = {
        "run_gate.json",
        "run_gate_summary.json",
        "findings_unified.json",
        "findings_unified.sarif",
        "reports/findings_unified.csv",
        "reports/findings_unified.html",
        "reports/findings_unified.tgz",
        "reports/findings_unified.zip",
        "SUMMARY.txt",
    }

    _CACHE = {"rid2dir": {}}

    def _safe_rel(path: str) -> str:
        if not path:
            return ""
        path = path.strip().lstrip("/")
        if ".." in path.split("/"):
            return ""
        while "//" in path:
            path = path.replace("//", "/")
        return path

    def _max_bytes(rel: str) -> int:
        if rel.endswith(".tgz") or rel.endswith(".zip"):
            return 200 * 1024 * 1024
        if rel.endswith(".html"):
            return 80 * 1024 * 1024
        return 25 * 1024 * 1024

    def _deep_find_dir(rid: str):
        if not DEEP_ROOT:
            return None
        start = time.time()
        max_secs = 2.5
        max_dirs = 40000
        seen = 0
        root = Path(DEEP_ROOT)
        root_depth = len(root.parts)
        prune = {"node_modules", ".git", "__pycache__", ".venv", "venv", "dist", "build"}

        try:
            for cur, dirs, files in os.walk(root, topdown=True):
                seen += 1
                if seen > max_dirs or (time.time() - start) > max_secs:
                    return None
                pcur = Path(cur)
                depth = len(pcur.parts) - root_depth
                if depth > 6:
                    dirs[:] = []
                    continue
                dirs[:] = [d for d in dirs if d not in prune]
                if pcur.name == rid:
                    return pcur
        except Exception:
            return None
        return None

    def _find_run_dir(rid: str):
        rid = (rid or "").strip()
        if not rid:
            return None
        if rid in _CACHE["rid2dir"]:
            v = _CACHE["rid2dir"][rid]
            return Path(v) if v else None

        # direct
        for b in BASE_DIRS:
            cand = Path(b) / rid
            if cand.is_dir():
                _CACHE["rid2dir"][rid] = str(cand)
                return cand

        # shallow depth 2
        for b in BASE_DIRS:
            base = Path(b)
            try:
                for d1 in base.iterdir():
                    if not d1.is_dir(): continue
                    cand = d1 / rid
                    if cand.is_dir():
                        _CACHE["rid2dir"][rid] = str(cand)
                        return cand
                for d1 in base.iterdir():
                    if not d1.is_dir(): continue
                    for d2 in d1.iterdir():
                        if not d2.is_dir(): continue
                        cand = d2 / rid
                        if cand.is_dir():
                            _CACHE["rid2dir"][rid] = str(cand)
                            return cand
            except Exception:
                pass

        # deep bounded
        cand = _deep_find_dir(rid)
        if cand and cand.is_dir():
            _CACHE["rid2dir"][rid] = str(cand)
            return cand

        _CACHE["rid2dir"][rid] = ""
        return None

    def _resolve_safe(run_dir: Path, rel: str):
        fp = (run_dir / rel)
        try:
            fp_res = fp.resolve()
            rd_res = run_dir.resolve()
            if rd_res not in fp_res.parents and fp_res != rd_res:
                return None
            return fp_res
        except Exception:
            return None

    def vsp_run_file_v4():
        rid = (request.args.get("rid") or "").strip()
        rel = _safe_rel(request.args.get("path") or "")
        if not rid or not rel:
            return jsonify({"ok": False, "err": "missing rid/path"}), 400

        # keep "no auto probe" policy at UI-level; backend remains read-only whitelist
        if rel not in ALLOW:
            return jsonify({"ok": False, "err": "path not allowed", "allow": sorted(ALLOW)}), 403

        run_dir = _find_run_dir(rid)
        if not run_dir:
            return jsonify({"ok": False, "err": "run_dir not found", "rid": rid, "roots_used": BASE_DIRS, "deep_root": DEEP_ROOT}), 404

        rel_try = [rel]
        if rel == "run_gate.json":
            rel_try = ["run_gate.json", "run_gate_summary.json", "SUMMARY.txt"]

        picked = None
        for rr in rel_try:
            fp = _resolve_safe(run_dir, rr)
            if fp and fp.exists() and fp.is_file():
                picked = (rr, fp)
                break

        if not picked:
            exists = []
            for rr in sorted(ALLOW):
                fp = _resolve_safe(run_dir, rr)
                if fp and fp.exists() and fp.is_file():
                    exists.append(rr)
            return jsonify({"ok": False, "err": "file not found", "rid": rid, "path": rel, "run_dir": str(run_dir), "has": exists}), 404

        rr, fp = picked
        try:
            sz = fp.stat().st_size
        except Exception:
            sz = -1
        lim = _max_bytes(rr)
        if sz >= 0 and sz > lim:
            return jsonify({"ok": False, "err": "file too large", "size": sz, "limit": lim, "path": rr}), 413

        mime, _ = mimetypes.guess_type(str(fp))
        mime = mime or "application/octet-stream"
        as_attach = rr.endswith(".tgz") or rr.endswith(".zip")
        dl_name = f"{rid}__{rr.replace('/','_')}"
        resp = send_file(str(fp), mimetype=mime, as_attachment=as_attach, download_name=dl_name)
        try:
            if rr != rel:
                resp.headers["X-VSP-Fallback-Path"] = rr
        except Exception:
            pass
        return resp

    # FORCE override any existing endpoint bound to path "/api/vsp/run_file"
    endpoints = []
    try:
        for rule in app_obj.url_map.iter_rules():
            if getattr(rule, "rule", "") == "/api/vsp/run_file":
                endpoints.append(rule.endpoint)
    except Exception:
        endpoints = []

    ok = False
    for ep in set(endpoints):
        try:
            app_obj.view_functions[ep] = vsp_run_file_v4
            ok = True
        except Exception:
            pass

    if ok:
        print(f"[VSP_RUN_FILE] V4 force-bound endpoints={sorted(set(endpoints))}")
        return True

    # if no rule existed, mount it
    try:
        app_obj.add_url_rule("/api/vsp/run_file", "vsp_run_file_v4", vsp_run_file_v4, methods=["GET"])
        print("[VSP_RUN_FILE] V4 mounted fresh /api/vsp/run_file")
        return True
    except Exception as e:
        print("[VSP_RUN_FILE] V4 mount failed:", e)
        return False
# --- end VSP_P1_FORCE_RUN_FILE_HANDLER_V4 ---
''').strip("\n") + "\n"

targets = [Path("wsgi_vsp_ui_gateway.py"), Path("vsp_demo_app.py"), Path("ui/vsp_demo_app.py")]
for p in targets:
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[OK] already patched:", p)
        continue
    s2 = s + "\n\n# " + marker + "\n" + block + "\n" + textwrap.dedent(r'''
# auto-bind on import (best-effort)
try:
    _app = globals().get("app", None) or globals().get("application", None)
    _vsp_p1_force_run_file_handler_v4(_app)
except Exception:
    pass
''').strip("\n") + "\n"
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched:", p)
PY

sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1&offset=0" | python3 -c 'import sys,json; j=json.load(sys.stdin); it=(j.get("items") or [{}])[0]; print(it.get("rid") or it.get("run_id") or "")' 2>/dev/null || true)"
echo "[RID]=$RID"

echo "== try allowlisted files =="
for P in "run_gate.json" "run_gate_summary.json" "SUMMARY.txt" "findings_unified.json"; do
  echo "--- $P ---"
  curl -sS -D /tmp/vsp_runfile_hdr.txt "$BASE/api/vsp/run_file?rid=$RID&path=$P" | head -c 180; echo
  grep -i "X-VSP-Fallback-Path" /tmp/vsp_runfile_hdr.txt || true
done
