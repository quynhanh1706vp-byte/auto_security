#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

TS="$(date +%Y%m%d_%H%M%S)"

# ưu tiên patch file “gateway/app” thường dùng
TARGET=""
for f in wsgi_vsp_ui_gateway.py vsp_demo_app.py; do
  if [ -f "$f" ]; then TARGET="$f"; break; fi
done
[ -n "$TARGET" ] || { echo "[ERR] cannot find wsgi_vsp_ui_gateway.py or vsp_demo_app.py"; exit 2; }

cp -f "$TARGET" "${TARGET}.bak_open_api_${TS}"
echo "[BACKUP] ${TARGET}.bak_open_api_${TS}"

python3 - <<'PY'
from pathlib import Path
import os, textwrap

# pick same target as shell
target = None
for f in ["wsgi_vsp_ui_gateway.py","vsp_demo_app.py"]:
    if Path(f).exists():
        target = f
        break
p = Path(target)
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_OPEN_API_STUB_P0_V1"
if marker in s:
    print("[OK] marker already present:", marker)
    raise SystemExit(0)

block = textwrap.dedent(f"""
# --- {marker} ---
# Purpose: Runs tab may probe /api/vsp/open*; avoid 404 spam.
# Commercial-safe default: NO server-side opener unless VSP_UI_ALLOW_XDG_OPEN=1 (dev only).
try:
    from flask import request, jsonify
    import os as _os
    from pathlib import Path as _Path
    import subprocess as _subprocess
except Exception:
    request = None
    jsonify = None

def _vsp_try_find_run_dir(_rid: str):
    if not _rid:
        return None
    roots = [
        _os.environ.get("VSP_RUNS_ROOT", ""),
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        str(_Path(__file__).resolve().parent / "out"),
        str(_Path(__file__).resolve().parent.parent / "out"),
        str(_Path(__file__).resolve().parent / "out_ci"),
        str(_Path(__file__).resolve().parent.parent / "out_ci"),
    ]
    for r in roots:
        if not r:
            continue
        base = _Path(r)
        cand = base / _rid
        if cand.exists():
            return str(cand.resolve())
        # cheap depth-2 search
        try:
            for sub in base.glob("*"):
                if sub.is_dir():
                    cand2 = sub / _rid
                    if cand2.exists():
                        return str(cand2.resolve())
        except Exception:
            pass
    return None

def _vsp_open_payload(rid: str, what: str):
    run_dir = _vsp_try_find_run_dir(rid)
    allow = _os.environ.get("VSP_UI_ALLOW_XDG_OPEN", "0") == "1"
    opened = False
    err = None
    if allow and run_dir and what in ("folder","dir","run_dir"):
        try:
            _subprocess.Popen(["xdg-open", run_dir],
                              stdout=_subprocess.DEVNULL, stderr=_subprocess.DEVNULL)
            opened = True
        except Exception as e:
            err = str(e)
    payload = {{
        "ok": True,
        "rid": rid,
        "what": what,
        "run_dir": run_dir,
        "opened": opened,
        "disabled": (not allow),
        "hint": "SAFE default: opener disabled. Set VSP_UI_ALLOW_XDG_OPEN=1 to enable (dev only)."
    }}
    if err:
        payload["error"] = err
    return payload

try:
    _app_obj = globals().get("app") or globals().get("application")
    if _app_obj is not None and request is not None and jsonify is not None:
        @_app_obj.route("/api/vsp/open", methods=["GET"])
        def vsp_open_p0_v1():
            rid = (request.args.get("rid","") or "").strip()
            what = (request.args.get("what","folder") or "folder").strip()
            return jsonify(_vsp_open_payload(rid, what))

        @_app_obj.route("/api/vsp/open_folder", methods=["GET"])
        def vsp_open_folder_p0_v1():
            rid = (request.args.get("rid","") or "").strip()
            return jsonify(_vsp_open_payload(rid, "folder"))
except Exception:
    pass
""").strip() + "\n"

p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
print("[OK] appended", marker, "to", p)
PY

python3 -m py_compile "$TARGET"
echo "[OK] py_compile OK"

echo "== NOTE: restart your UI service now =="
echo " - systemd: sudo systemctl restart vsp-ui-8910.service"
echo " - or your start script for :8910"

echo "== quick verify (expect JSON, no 404) =="
curl -fsS "http://127.0.0.1:8910/api/vsp/open" | head -c 200; echo
