#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
FILES=()
[ -f wsgi_vsp_ui_gateway.py ] && FILES+=(wsgi_vsp_ui_gateway.py)
[ -f ui/vsp_demo_app.py ] && FILES+=(ui/vsp_demo_app.py)
[ -f vsp_demo_app.py ] && FILES+=(vsp_demo_app.py)

[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] no target python files found"; exit 2; }

for F in "${FILES[@]}"; do
  cp -f "$F" "${F}.bak_runfile_mount_${TS}"
  echo "[BACKUP] ${F}.bak_runfile_mount_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import textwrap, re

marker = "VSP_P1_RUN_FILE_WHITELIST_V2_MOUNT"
block = textwrap.dedent(r'''
# --- VSP_P1_RUN_FILE_WHITELIST_V2_MOUNT: safe run_file endpoint (whitelist + no traversal) ---
def _vsp_p1_run_file_register_v2(app_obj):
    try:
        import os, mimetypes
        from pathlib import Path
        from flask import request, jsonify, send_file
    except Exception:
        return False

    if not app_obj or not hasattr(app_obj, "add_url_rule"):
        return False

    try:
        if hasattr(app_obj, "view_functions") and ("vsp_run_file_whitelist_v2" in app_obj.view_functions):
            return True
    except Exception:
        pass

    BASE_DIRS = [
        os.environ.get("VSP_OUT_DIR", "") or "",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    ]
    BASE_DIRS = [d for d in BASE_DIRS if d and os.path.isdir(d)]

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

    def _find_run_dir(rid: str):
        rid = (rid or "").strip()
        if not rid:
            return None
        if rid in _CACHE["rid2dir"]:
            v = _CACHE["rid2dir"][rid]
            return Path(v) if v else None

        for b in BASE_DIRS:
            cand = Path(b) / rid
            if cand.is_dir():
                _CACHE["rid2dir"][rid] = str(cand)
                return cand

        # bounded shallow search
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
                continue

        _CACHE["rid2dir"][rid] = ""
        return None

    def vsp_run_file_whitelist_v2():
        rid = (request.args.get("rid") or "").strip()
        rel = _safe_rel(request.args.get("path") or "")
        if not rid or not rel:
            return jsonify({"ok": False, "err": "missing rid/path"}), 400
        if rel not in ALLOW:
            return jsonify({"ok": False, "err": "path not allowed", "allow": sorted(ALLOW)}), 403

        run_dir = _find_run_dir(rid)
        if not run_dir:
            return jsonify({"ok": False, "err": "run_dir not found", "rid": rid, "roots_used": BASE_DIRS}), 404

        fp = (run_dir / rel)
        try:
            fp_res = fp.resolve()
            rd_res = run_dir.resolve()
            if rd_res not in fp_res.parents and fp_res != rd_res:
                return jsonify({"ok": False, "err": "blocked escape"}), 403
        except Exception:
            return jsonify({"ok": False, "err": "resolve failed"}), 403

        if not fp.exists() or not fp.is_file():
            return jsonify({"ok": False, "err": "file not found", "path": rel}), 404

        try:
            sz = fp.stat().st_size
        except Exception:
            sz = -1
        lim = _max_bytes(rel)
        if sz >= 0 and sz > lim:
            return jsonify({"ok": False, "err": "file too large", "size": sz, "limit": lim}), 413

        mime, _ = mimetypes.guess_type(str(fp))
        mime = mime or "application/octet-stream"
        as_attach = rel.endswith(".tgz") or rel.endswith(".zip")
        dl_name = f"{rid}__{rel.replace('/','_')}"
        return send_file(str(fp), mimetype=mime, as_attachment=as_attach, download_name=dl_name)

    try:
        app_obj.add_url_rule("/api/vsp/run_file", "vsp_run_file_whitelist_v2", vsp_run_file_whitelist_v2, methods=["GET"])
        print("[VSP_RUN_FILE] mounted /api/vsp/run_file (v2 whitelist)")
        return True
    except Exception as e:
        print("[VSP_RUN_FILE] mount failed:", e)
        return False
# --- end VSP_P1_RUN_FILE_WHITELIST_V2_MOUNT ---
''').strip("\n") + "\n"

targets = [Path("wsgi_vsp_ui_gateway.py"), Path("ui/vsp_demo_app.py"), Path("vsp_demo_app.py")]
for p in targets:
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[OK] already patched:", p)
        continue

    # append block
    s2 = s + "\n\n# " + marker + "\n" + block

    # try to auto-call register with common app objects
    call = textwrap.dedent(r'''
# auto-register run_file on import (best-effort)
try:
    _app = globals().get("app", None) or globals().get("application", None)
    _vsp_p1_run_file_register_v2(_app)
except Exception:
    pass
''').strip("\n") + "\n"

    s2 += "\n" + call
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched:", p)
PY

echo "== py_compile check =="
python3 -m py_compile wsgi_vsp_ui_gateway.py 2>/dev/null || true
python3 -m py_compile ui/vsp_demo_app.py 2>/dev/null || true
python3 -m py_compile vsp_demo_app.py 2>/dev/null || true
echo "[OK] compile attempted"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== smoke route presence =="
curl -fsS -I "$BASE/api/vsp/run_file" | head -n 12 || true
echo "== get rid =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1&offset=0" | python3 -c 'import sys,json; j=json.load(sys.stdin); it=(j.get("items") or [{}])[0]; print(it.get("rid") or it.get("run_id") or "")' 2>/dev/null || true)"
echo "[RID]=$RID"
if [ -n "$RID" ]; then
  echo "== run_gate.json head =="
  curl -fsS "$BASE/api/vsp/run_file?rid=$RID&path=run_gate.json" | head -c 300; echo
else
  echo "[WARN] no RID from /api/vsp/runs"
fi

echo "[DONE] If /api/vsp/run_file now returns 400 (missing rid/path) => route is mounted OK."
