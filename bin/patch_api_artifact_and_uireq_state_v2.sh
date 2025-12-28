#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_art_uireq_${TS}"
echo "[BACKUP] $F.bak_art_uireq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "# === VSP API ARTIFACT+UIREQ STATE V2 ==="
if MARK in txt:
    print("[OK] block already present")
    sys.exit(0)

block = r'''
# === VSP API ARTIFACT+UIREQ STATE V2 ===
from pathlib import Path
import os, json
from flask import request, send_file, jsonify, Response, abort

_UIROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
_UIREQ_DIR = _UIROOT / "out_ci" / "uireq_v1"
_UIREQ_DIR.mkdir(parents=True, exist_ok=True)

def _safe_join(base: Path, rel: str) -> Path:
    rel = (rel or "").lstrip("/").replace("\\", "/")
    # block traversal
    if ".." in rel.split("/"):
        raise ValueError("path traversal")
    out = (base / rel).resolve()
    base_r = base.resolve()
    if str(out) != str(base_r) and not str(out).startswith(str(base_r) + os.sep):
        raise ValueError("outside base")
    return out

def _guess_mime(path: str) -> str:
    s = (path or "").lower()
    if s.endswith(".json"): return "application/json; charset=utf-8"
    if s.endswith(".html") or s.endswith(".htm"): return "text/html; charset=utf-8"
    if s.endswith(".txt") or s.endswith(".log"): return "text/plain; charset=utf-8"
    if s.endswith(".zip"): return "application/zip"
    if s.endswith(".sarif"): return "application/sarif+json; charset=utf-8"
    return "application/octet-stream"

@app.get("/api/vsp/uireq_state_v1/<rid>")
def vsp_uireq_state_v1(rid):
    try:
        fp = _safe_join(_UIREQ_DIR, f"{rid}.json")
        if not fp.exists():
            return jsonify({"ok": False, "rid": rid, "error": "uireq_state_not_found"}), 404
        data = json.loads(fp.read_text(encoding="utf-8", errors="ignore") or "{}")
        if isinstance(data, dict):
            data.setdefault("ok", True)
            data.setdefault("rid", rid)
            return jsonify(data), 200
        return jsonify({"ok": True, "rid": rid, "data": data}), 200
    except Exception as e:
        return jsonify({"ok": False, "rid": rid, "error": str(e)}), 500

@app.get("/api/vsp/run_artifact_v1/<rid>")
def vsp_run_artifact_v1(rid):
    """
    Read artifact file by rid.
    - Query: path=relative/path inside ci_run_dir OR inside ui/out_ci/uireq_v1
    - Safe against traversal
    """
    rel = request.args.get("path", "") or ""
    if not rel:
        return jsonify({"ok": False, "rid": rid, "error": "missing_path"}), 400

    # resolve base folders
    # 1) if uireq state exists, allow direct read
    bases = []
    try:
        bases.append(_UIREQ_DIR)
    except Exception:
        pass

    # 2) try infer CI run dir from status API (best effort)
    ci_dir = None
    try:
        # call local function if exists (avoid HTTP)
        if "vsp_run_status_v1" in globals():
            st = vsp_run_status_v1(rid)
            # flask can return tuple/resp
            payload = None
            if isinstance(st, tuple):
                resp = st[0]
                if hasattr(resp, "get_json"):
                    payload = resp.get_json(silent=True)
            elif hasattr(st, "get_json"):
                payload = st.get_json(silent=True)
            if isinstance(payload, dict):
                ci_dir = payload.get("ci_run_dir") or payload.get("ci_dir")
    except Exception:
        ci_dir = None

    if ci_dir:
        try:
            bases.append(Path(ci_dir))
        except Exception:
            pass

    # fallback: allow under ui/out_ci (for dev logs)
    bases.append(_UIROOT / "out_ci")

    last_err = None
    for base in bases:
        try:
            fp = _safe_join(base, rel)
            if fp.exists() and fp.is_file():
                mime = _guess_mime(rel)
                # stream bytes
                data = fp.read_bytes()
                return Response(data, status=200, mimetype=mime)
        except Exception as e:
            last_err = e
            continue

    return jsonify({"ok": False, "rid": rid, "error": "artifact_not_found", "path": rel, "detail": str(last_err) if last_err else ""}), 404
# === END VSP API ARTIFACT+UIREQ STATE V2 ===
'''

txt2 = txt.rstrip() + "\n\n" + block + "\n"
p.write_text(txt2, encoding="utf-8")
print("[OK] appended ARTIFACT+UIREQ API V2")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile"
