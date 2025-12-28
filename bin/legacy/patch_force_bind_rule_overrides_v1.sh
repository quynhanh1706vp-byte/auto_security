#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

if grep -q "VSP_RULE_OVERRIDES_FORCE_BIND_V1" "$F"; then
  echo "[OK] force bind already present, skip"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rule_overrides_force_${TS}"
echo "[BACKUP] $F.bak_rule_overrides_force_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

block = r"""
# === VSP_RULE_OVERRIDES_FORCE_BIND_V1 BEGIN ===
import json as _json
from pathlib import Path as _Path
from datetime import datetime as _dt, timezone as _tz
import os as _os
import tempfile as _tempfile

_VSP_RULE_OVR_PATH = _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_rule_overrides_v1.json")

def _vsp_rule_ovr_default_v1():
    return {"meta":{"version":"v1","updated_at":None},"overrides":[]}

def _vsp_rule_ovr_atomic_write_v1(path:_Path, obj:dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = _tempfile.mkstemp(prefix=path.name+".", dir=str(path.parent))
    try:
        with _os.fdopen(fd, "w", encoding="utf-8") as f:
            _json.dump(obj, f, ensure_ascii=False, indent=2)
        _os.replace(tmp, str(path))
    finally:
        try:
            _os.unlink(tmp)
        except Exception:
            pass

class VSPRuleOverridesForceBindV1:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/rule_overrides_v1"):
            return self.app(environ, start_response)

        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        try:
            if method == "GET":
                if _VSP_RULE_OVR_PATH.exists():
                    try:
                        data = _json.load(open(_VSP_RULE_OVR_PATH, "r", encoding="utf-8"))
                    except Exception:
                        data = _vsp_rule_ovr_default_v1()
                else:
                    data = _vsp_rule_ovr_default_v1()

                body = _json.dumps(data, ensure_ascii=False).encode("utf-8")
                hdrs = [
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                    ("Cache-Control","no-cache"),
                    ("X-VSP-RULE-OVERRIDES-MODE","FORCE_BIND_V1"),
                ]
                start_response("200 OK", hdrs)
                return [body]

            if method == "POST":
                try:
                    n = int(environ.get("CONTENT_LENGTH") or "0")
                except Exception:
                    n = 0
                raw = environ["wsgi.input"].read(n) if n > 0 else b"{}"
                obj = _json.loads(raw.decode("utf-8", errors="replace") or "{}")
                if not isinstance(obj, dict):
                    obj = _vsp_rule_ovr_default_v1()
                obj.setdefault("meta", {})
                obj["meta"]["updated_at"] = _dt.now(_tz.utc).isoformat()
                _vsp_rule_ovr_atomic_write_v1(_VSP_RULE_OVR_PATH, obj)

                out = {"ok": True, "file": str(_VSP_RULE_OVR_PATH), "mode":"FORCE_BIND_V1"}
                body = _json.dumps(out, ensure_ascii=False).encode("utf-8")
                hdrs = [
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                    ("Cache-Control","no-cache"),
                    ("X-VSP-RULE-OVERRIDES-MODE","FORCE_BIND_V1"),
                ]
                start_response("200 OK", hdrs)
                return [body]

            body = b'{"ok":false,"error":"METHOD_NOT_ALLOWED"}'
            start_response("405 Method Not Allowed", [
                ("Content-Type","application/json; charset=utf-8"),
                ("Content-Length", str(len(body))),
            ])
            return [body]
        except Exception as e:
            body = _json.dumps({"ok":False,"error":"RULE_OVERRIDES_FORCE_BIND_ERR","detail":str(e)}, ensure_ascii=False).encode("utf-8")
            start_response("500 Internal Server Error", [
                ("Content-Type","application/json; charset=utf-8"),
                ("Content-Length", str(len(body))),
                ("X-VSP-RULE-OVERRIDES-MODE","FORCE_BIND_V1"),
            ])
            return [body]
# === VSP_RULE_OVERRIDES_FORCE_BIND_V1 END ===
"""

# insert block near end (before application export if possible)
if "VSP_RULE_OVERRIDES_FORCE_BIND_V1 BEGIN" in s:
    raise SystemExit("already present")

s += "\n" + block + "\n"

# wrap existing application
if re.search(r'\bapplication\s*=\s*VSPRuleOverridesForceBindV1\(', s):
    pass
else:
    # append wrapper at very end
    s += "\n# VSP_RULE_OVERRIDES_FORCE_BIND_V1 WRAP\napplication = VSPRuleOverridesForceBindV1(application)\n"

p.write_text(s, encoding="utf-8")
print("[OK] appended middleware + wrapped application")
PY

python3 -m py_compile "$F"
echo "[OK] patched + py_compile OK => $F"
