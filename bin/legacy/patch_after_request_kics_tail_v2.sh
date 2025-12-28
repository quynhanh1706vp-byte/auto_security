#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
import re, subprocess
from pathlib import Path

ROOT = Path(".").resolve()
TAG_HELP = "VSP_KICS_TAIL_HELPERS_V2"
TAG_AR   = "VSP_AFTER_REQUEST_INJECT_KICS_TAIL_V2"

files = sorted(ROOT.glob("**/vsp_demo_app.py"))
print(f"[INFO] found {len(files)} vsp_demo_app.py")
for f in files:
    print(" -", f.relative_to(ROOT))

def insert_after_imports(txt: str, payload: str) -> str:
    m = re.search(r"(?ms)\A(.*?\n)(\s*(?:from|import)\s+[^\n]+\n(?:\s*(?:from|import)\s+[^\n]+\n)*)", txt)
    pos = m.end(0) if m else 0
    return txt[:pos] + payload + txt[pos:]

HELPER = r'''
# === __TAG_HELP__ ===
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

AFTER_REQ = r'''
# === __TAG_AR__ ===
def _vsp__inject_kics_tail_to_response(resp):
    try:
        from flask import request as _req
        import json as _json

        path = (_req.path or "")
        if not path.startswith("/api/vsp/run_status_v1/"):
            return resp

        # try flask response json first
        obj = None
        try:
            obj = resp.get_json(silent=True)
        except Exception:
            obj = None

        if obj is None:
            raw = resp.get_data(as_text=True) or ""
            if not raw.strip():
                return resp
            try:
                obj = _json.loads(raw)
            except Exception:
                return resp

        if not isinstance(obj, dict):
            return resp

        if "kics_tail" not in obj:
            ci = obj.get("ci_run_dir") or obj.get("ci_dir") or obj.get("ci_run") or ""
            kt = _vsp_kics_tail_from_ci(ci) if ci else ""
            obj["kics_tail"] = kt if isinstance(kt, str) else str(kt)
        else:
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

# bind to app if present
try:
    @app.after_request
    def __vsp_after_request_kics_tail_v2(resp):
        return _vsp__inject_kics_tail_to_response(resp)
except Exception:
    pass

# bind to bp if module uses blueprint
try:
    @bp.after_request
    def __vsp_bp_after_request_kics_tail_v2(resp):
        return _vsp__inject_kics_tail_to_response(resp)
except Exception:
    pass
# === END __TAG_AR__ ===
'''.replace("__TAG_AR__", TAG_AR)

patched = 0
for fp in files:
    txt = fp.read_text(encoding="utf-8", errors="ignore")
    changed = False

    # safe replace canonical path typo
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
        txt = txt.rstrip() + "\n\n" + AFTER_REQ + "\n"
        changed = True

    if changed:
        bak = fp.with_suffix(fp.suffix + f".bak_kics_tail_ar_v2_{Path().name}")
        # don't use weird suffix; create explicit backup file next to it
        bak = fp.parent / (fp.name + f".bak_kics_tail_ar_v2_{__import__('time').strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(fp.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
        fp.write_text(txt, encoding="utf-8")
        print("[OK] patched", fp.relative_to(ROOT), "backup:", bak.name)
        patched += 1
    else:
        print("[OK] already patched", fp.relative_to(ROOT))

print("[INFO] patched_files =", patched)

# py_compile all
import py_compile
for fp in files:
    py_compile.compile(str(fp), doraise=True)
    print("[OK] py_compile", fp.relative_to(ROOT))
PY

echo "[DONE] after_request patch v2 applied"
