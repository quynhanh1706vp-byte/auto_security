#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

TAG_HELP="VSP_KICS_TAIL_HELPERS_V2"
TAG_AR="VSP_AFTER_REQUEST_INJECT_KICS_TAIL_V1"

mapfile -t FILES < <(find . -maxdepth 8 -name 'vsp_demo_app.py' -type f | sort)
[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] no vsp_demo_app.py found"; exit 1; }

echo "[INFO] will patch ${#FILES[@]} file(s):"
printf ' - %s\n' "${FILES[@]}"

python3 - <<'PY'
import os, re
from pathlib import Path

TAG_HELP=os.environ.get("TAG_HELP","VSP_KICS_TAIL_HELPERS_V2")
TAG_AR=os.environ.get("TAG_AR","VSP_AFTER_REQUEST_INJECT_KICS_TAIL_V1")
files=os.environ["FILES"].splitlines()

def insert_after_imports(txt, payload):
    m = re.search(r"(?ms)\A(.*?\n)(\s*(?:from|import)\s+[^\n]+\n(?:\s*(?:from|import)\s+[^\n]+\n)*)", txt)
    pos = m.end(0) if m else 0
    return txt[:pos] + payload + txt[pos:]

HELPER = r'''
# === __TAG_HELP__ ===
# local-safe helpers (avoid f-string braces issues)
import json as _vsp_json
from pathlib import Path as _vsp_Path

def _vsp_safe_tail_text(_p, max_bytes=8192, max_lines=120):
    try:
        _p = _vsp_Path(_p)
        if not _p.exists():
            return ""
        b = _p.read_bytes()
    except Exception:
        return ""
    if max_bytes and len(b) > max_bytes:
        b = b[-max_bytes:]
    try:
        s = b.decode("utf-8", errors="replace")
    except Exception:
        s = str(b)
    lines = s.splitlines()
    if max_lines and len(lines) > max_lines:
        lines = lines[-max_lines:]
    return "\n".join(lines).strip()

def _vsp_kics_tail_from_ci(ci_run_dir):
    if not ci_run_dir:
        return ""
    try:
        base = _vsp_Path(str(ci_run_dir))
    except Exception:
        return ""
    klog = base / "kics" / "kics.log"
    if klog.exists():
        return _vsp_safe_tail_text(klog)

    djson = base / "degraded_tools.json"
    if djson.exists():
        try:
            raw = djson.read_text(encoding="utf-8", errors="ignore").strip() or "[]"
            data = _vsp_json.loads(raw)
            items = data.get("degraded_tools", []) if isinstance(data, dict) else data
            for it in (items or []):
                tool = str((it or {}).get("tool","")).upper()
                if tool == "KICS":
                    rc = (it or {}).get("rc")
                    reason = (it or {}).get("reason") or (it or {}).get("msg") or "degraded"
                    return "MISSING_TOOL: KICS (rc=%s) reason=%s" % (rc, reason)
        except Exception:
            pass

    if (base / "kics").exists():
        return "NO_KICS_LOG: %s" % (klog,)
    return ""
# === END __TAG_HELP__ ===
'''.replace("__TAG_HELP__", TAG_HELP)

AFTER_REQUEST_APP = r'''
# === __TAG_AR__ ===
def _vsp__inject_kics_tail_to_response(resp):
    try:
        # lazy imports (avoid dependency on import order)
        from flask import request as _req
        import json as _json
        path = (_req.path or "")
        if not path.startswith("/api/vsp/run_status_v1/"):
            return resp
        if getattr(resp, "mimetype", "") != "application/json":
            # still try if it's JSON string
            pass

        raw = resp.get_data(as_text=True)
        if not raw:
            return resp
        try:
            obj = _json.loads(raw)
        except Exception:
            return resp

        if isinstance(obj, dict):
            if "kics_tail" not in obj:
                ci = obj.get("ci_run_dir") or obj.get("ci_dir") or obj.get("ci_run") or ""
                kt = _vsp_kics_tail_from_ci(ci) if ci else ""
                obj["kics_tail"] = kt if isinstance(kt, str) else str(kt)
            else:
                # normalize non-string to string
                kt = obj.get("kics_tail")
                if kt is None:
                    obj["kics_tail"] = ""
                elif not isinstance(kt, str):
                    obj["kics_tail"] = str(kt)

            obj.setdefault("_handler", "after_request_inject:/api/vsp/run_status_v1")
            resp.set_data(_json.dumps(obj, ensure_ascii=False))
            resp.mimetype = "application/json"
        return resp
    except Exception:
        return resp

# attach to app if possible
try:
    @app.after_request
    def __vsp_after_request_inject_kics_tail_v1(resp):
        return _vsp__inject_kics_tail_to_response(resp)
except Exception:
    pass

# attach to blueprint if app isn't in this module
try:
    @bp.after_request
    def __vsp_bp_after_request_inject_kics_tail_v1(resp):
        return _vsp__inject_kics_tail_to_response(resp)
except Exception:
    pass
# === END __TAG_AR__ ===
'''.replace("__TAG_AR__", TAG_AR)

for fp in files:
    p = Path(fp)
    txt = p.read_text(encoding="utf-8", errors="ignore")
    changed = False

    # optional: fix double ui path strings
    for a,b in {
      "ui/ui/out_ci/uireq_v1": "ui/out_ci/uireq_v1",
      "/ui/ui/out_ci/uireq_v1": "/ui/out_ci/uireq_v1",
    }.items():
        if a in txt:
            txt = txt.replace(a,b); changed = True

    if TAG_HELP not in txt:
        txt = insert_after_imports(txt, HELPER)
        changed = True

    if TAG_AR not in txt:
        # append at end (safe, does not depend on route code)
        txt = txt.rstrip() + "\n\n" + AFTER_REQUEST_APP + "\n"
        changed = True

    if changed:
        p.write_text(txt, encoding="utf-8")
        print("[OK] patched", fp)
    else:
        print("[OK] skip (already patched)", fp)
PY
