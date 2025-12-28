#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

# --- backend targets ---
PY_FILES=()
[ -f wsgi_vsp_ui_gateway.py ] && PY_FILES+=(wsgi_vsp_ui_gateway.py)
[ -f vsp_demo_app.py ] && PY_FILES+=(vsp_demo_app.py)
[ -f ui/vsp_demo_app.py ] && PY_FILES+=(ui/vsp_demo_app.py)

[ "${#PY_FILES[@]}" -gt 0 ] || { echo "[ERR] no python backend files found"; exit 2; }

for f in "${PY_FILES[@]}"; do
  cp -f "$f" "${f}.bak_runfile_allow_v5_${TS}"
  echo "[BACKUP] ${f}.bak_runfile_allow_v5_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import textwrap, os

marker = "VSP_P1_RUN_FILE_ALLOW_V5"

block = textwrap.dedent(r'''
# --- VSP_P1_RUN_FILE_ALLOW_V5: separate allow endpoint (keeps /api/vsp/run_file policy OFF) ---
def _vsp_p1_register_run_file_allow_v5(app_obj):
    try:
        import os, time, mimetypes
        from pathlib import Path
        from flask import request, jsonify, send_file
    except Exception:
        return False
    if not app_obj or not hasattr(app_obj, "add_url_rule"):
        return False

    # avoid double register
    try:
        if hasattr(app_obj, "view_functions") and ("vsp_run_file_allow_v5" in app_obj.view_functions):
            return True
    except Exception:
        pass

    BASE_DIRS = [
        os.environ.get("VSP_OUT_DIR", "") or "",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]
    BASE_DIRS = [d for d in BASE_DIRS if d and os.path.isdir(d)]

    # bounded deep find root (only on demand)
    DEEP_ROOT = os.environ.get("VSP_DEEP_RUN_ROOT", "/home/test/Data")
    if not os.path.isdir(DEEP_ROOT):
        DEEP_ROOT = ""

    # strict whitelist
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

        for b in BASE_DIRS:
            cand = Path(b) / rid
            if cand.is_dir():
                _CACHE["rid2dir"][rid] = str(cand)
                return cand

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

    def vsp_run_file_allow_v5():
        rid = (request.args.get("rid") or "").strip()
        rel = _safe_rel(request.args.get("path") or "")
        if not rid or not rel:
            return jsonify({"ok": False, "err": "missing rid/path"}), 400

        if rel not in ALLOW:
            return jsonify({"ok": False, "err": "not allowed", "allow": sorted(ALLOW)}), 403

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

    try:
        app_obj.add_url_rule("/api/vsp/run_file_allow", "vsp_run_file_allow_v5", vsp_run_file_allow_v5, methods=["GET"])
        print("[VSP_RUN_FILE_ALLOW] mounted /api/vsp/run_file_allow")
        return True
    except Exception as e:
        print("[VSP_RUN_FILE_ALLOW] mount failed:", e)
        return False
# --- end VSP_P1_RUN_FILE_ALLOW_V5 ---
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
try:
    _app = globals().get("app", None) or globals().get("application", None)
    _vsp_p1_register_run_file_allow_v5(_app)
except Exception:
    pass
''').strip("\n") + "\n"
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched:", p)
PY

# --- rewire UI JS: use /api/vsp/run_file_allow for click-open (keeps old /run_file off) ---
JS_FILES=()
[ -f static/js/vsp_runs_quick_actions_v1.js ] && JS_FILES+=(static/js/vsp_runs_quick_actions_v1.js)
[ -f static/js/vsp_bundle_commercial_v2.js ] && JS_FILES+=(static/js/vsp_bundle_commercial_v2.js)

for f in "${JS_FILES[@]}"; do
  cp -f "$f" "${f}.bak_runfile_allow_rewire_${TS}"
  echo "[BACKUP] ${f}.bak_runfile_allow_rewire_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

targets = [
  Path("static/js/vsp_runs_quick_actions_v1.js"),
  Path("static/js/vsp_bundle_commercial_v2.js"),
]
changed = 0
for p in targets:
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if "run_file_allow" in s:
        continue
    s2, n = re.subn(r"/api/vsp/run_file\b", "/api/vsp/run_file_allow", s)
    if n:
        p.write_text(s2, encoding="utf-8")
        print("[OK] rewired", p, "repl=", n)
        changed += 1
print("[OK] done, files_changed=", changed)
PY

sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2

echo "== verify allow endpoint mounted (expect 400 not 404) =="
curl -sS -I "$BASE/api/vsp/run_file_allow" | head -n 12 || true

RID="$(curl -sS "$BASE/api/vsp/runs?limit=1&offset=0" | python3 -c 'import sys,json; j=json.load(sys.stdin); it=(j.get("items") or [{}])[0]; print(it.get("rid") or it.get("run_id") or "")' 2>/dev/null || true)"
echo "[RID]=$RID"

if [ -n "$RID" ]; then
  echo "== try allow: run_gate.json =="
  curl -sS -D /tmp/vsp_allow_hdr.txt "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate.json" | head -c 220; echo
  grep -i "X-VSP-Fallback-Path" /tmp/vsp_allow_hdr.txt || true
fi

echo "[DONE] Now UI buttons Open JSON/HTML should hit /api/vsp/run_file_allow (click-only)."
