#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_apiui_post_${TS}"
echo "[BACKUP] ${W}.bak_apiui_post_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_APIUI_SHIM_POST_P1_V1"
if marker in s:
    print("[OK] marker already present, skip")
    raise SystemExit(0)

# Find the line that matches the existing shim branch for /api/ui/runs_v2
pos = s.find("/api/ui/runs_v2")
if pos < 0:
    print("[ERR] cannot find /api/ui/runs_v2 in wsgi; WSGI shim not found?")
    raise SystemExit(2)

# locate the start of that line
line_start = s.rfind("\n", 0, pos) + 1
line_end = s.find("\n", pos)
line = s[line_start:line_end]
m = re.match(r"^(\s*)(if|elif)\s+.*?/api/ui/runs_v2.*$", line)
if not m:
    # fallback: get indent from the line itself
    indent = re.match(r"^(\s*)", line).group(1)
else:
    indent = m.group(1)

# Build insertion block that must sit BEFORE existing runs_v2 branch
ins = f"""{indent}# === {marker} ===
{indent}# Handle POST endpoints in WSGI shim (because shim intercepts /api/ui/* before Flask routes)
{indent}import json as __json, time as __time
{indent}from pathlib import Path as __Path

{indent}__SETTINGS_PATH = __Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_settings_v2/settings.json")
{indent}__RULES_PATH    = __Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2/rules.json")
{indent}__APPLIED_DIR   = __Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2/applied")

{indent}def __wsgi_read_json(environ):
{indent}    try:
{indent}        n = int(environ.get("CONTENT_LENGTH") or 0)
{indent}    except Exception:
{indent}        n = 0
{indent}    raw = b""
{indent}    try:
{indent}        if n > 0:
{indent}            raw = environ["wsgi.input"].read(n) or b""
{indent}        else:
{indent}            raw = (environ.get("wsgi.input").read() or b"") if environ.get("wsgi.input") else b""
{indent}    except Exception:
{indent}        raw = b""
{indent}    txt = raw.decode("utf-8", errors="replace").strip()
{indent}    if not txt:
{indent}        return {{}}
{indent}    return __json.loads(txt)

{indent}def __wsgi_write_json(path: "__Path", obj):
{indent}    path.parent.mkdir(parents=True, exist_ok=True)
{indent}    tmp = path.with_suffix(path.suffix + f".tmp_{{int(__time.time())}}")
{indent}    tmp.write_text(__json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
{indent}    tmp.replace(path)

{indent}def __wsgi_json(payload, code=200):
{indent}    body = __json.dumps(payload, ensure_ascii=False).encode("utf-8")
{indent}    hdrs = [("Content-Type","application/json; charset=utf-8"),
{indent}            ("Cache-Control","no-store"),
{indent}            ("Content-Length", str(len(body)))]
{indent}    status = f"{{code}} " + ("OK" if code < 400 else "ERROR")
{indent}    return status, hdrs, [body]

{indent}# POST: /api/ui/settings_save_v2
{indent}if path == "/api/ui/settings_save_v2":
{indent}    if method != "POST":
{indent}        return __wsgi_json({{"ok": False, "error":"method_not_allowed","ts":int(__time.time())}}, 405)
{indent}    try:
{indent}        body = __wsgi_read_json(environ)
{indent}        settings = body.get("settings") if isinstance(body, dict) else None
{indent}        if settings is None and isinstance(body, dict):
{indent}            settings = body
{indent}        if not isinstance(settings, dict):
{indent}            return __wsgi_json({{"ok": False, "error":"settings_must_be_object","ts":int(__time.time())}}, 400)
{indent}        __wsgi_write_json(__SETTINGS_PATH, settings)
{indent}        return __wsgi_json({{"ok": True, "path": str(__SETTINGS_PATH), "settings": settings, "ts":int(__time.time())}}, 200)
{indent}    except Exception as e:
{indent}        return __wsgi_json({{"ok": False, "error": f"save_failed: {{e}}", "ts":int(__time.time())}}, 500)

{indent}# POST: /api/ui/rule_overrides_save_v2
{indent}if path == "/api/ui/rule_overrides_save_v2":
{indent}    if method != "POST":
{indent}        return __wsgi_json({{"ok": False, "error":"method_not_allowed","ts":int(__time.time())}}, 405)
{indent}    try:
{indent}        body = __wsgi_read_json(environ)
{indent}        data = body.get("data") if isinstance(body, dict) else None
{indent}        if data is None and isinstance(body, dict):
{indent}            data = body
{indent}        if not isinstance(data, dict):
{indent}            return __wsgi_json({{"ok": False, "error":"data_must_be_object","ts":int(__time.time())}}, 400)
{indent}        if "rules" not in data:
{indent}            data["rules"] = []
{indent}        if not isinstance(data.get("rules"), list):
{indent}            return __wsgi_json({{"ok": False, "error":"rules_must_be_array","ts":int(__time.time())}}, 400)
{indent}        __wsgi_write_json(__RULES_PATH, data)
{indent}        return __wsgi_json({{"ok": True, "path": str(__RULES_PATH), "data": data, "ts":int(__time.time())}}, 200)
{indent}    except Exception as e:
{indent}        return __wsgi_json({{"ok": False, "error": f"save_failed: {{e}}", "ts":int(__time.time())}}, 500)

{indent}# POST: /api/ui/rule_overrides_apply_v2?rid=...
{indent}if path == "/api/ui/rule_overrides_apply_v2":
{indent}    if method != "POST":
{indent}        return __wsgi_json({{"ok": False, "error":"method_not_allowed","ts":int(__time.time())}}, 405)
{indent}    try:
{indent}        qs = environ.get("QUERY_STRING","")
{indent}        rid = ""
{indent}        for part in qs.split("&"):
{indent}            if part.startswith("rid="):
{indent}                rid = part.split("=",1)[1].strip()
{indent}                break
{indent}        if not rid:
{indent}            return __wsgi_json({{"ok": False, "error":"missing_rid","ts":int(__time.time())}}, 400)
{indent}        try:
{indent}            body = __wsgi_read_json(environ)
{indent}            data = body.get("data") if isinstance(body, dict) else None
{indent}            if data is None and isinstance(body, dict):
{indent}                data = body
{indent}        except Exception:
{indent}            data = None
{indent}        if not isinstance(data, dict):
{indent}            # fallback to current rules file
{indent}            if __RULES_PATH.exists():
{indent}                data = __json.loads(__RULES_PATH.read_text(encoding="utf-8", errors="replace"))
{indent}            else:
{indent}                data = {{"rules":[]}}
{indent}        __APPLIED_DIR.mkdir(parents=True, exist_ok=True)
{indent}        out = __APPLIED_DIR / f"{{rid}}.json"
{indent}        payload = {{
{indent}            "rid": rid,
{indent}            "applied_at": int(__time.time()),
{indent}            "source_rules_path": str(__RULES_PATH),
{indent}            "applied_rules_path": str(out),
{indent}            "data": data,
{indent}        }}
{indent}        __wsgi_write_json(out, payload)
{indent}        return __wsgi_json({{"ok": True, **payload, "ts":int(__time.time())}}, 200)
{indent}    except Exception as e:
{indent}        return __wsgi_json({{"ok": False, "error": f"apply_failed: {{e}}", "ts":int(__time.time())}}, 500)
{indent}# === /{marker} ===
"""

s2 = s[:line_start] + ins + s[line_start:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted POST handlers into shim:", marker)
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 1.2

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify POST endpoints (must be 200 ok:true) =="
curl -sS -i "$BASE/api/ui/settings_save_v2" -H 'Content-Type: application/json' -d '{"settings":{"degrade_graceful":true}}' | sed -n '1,14p'
echo
curl -sS -i "$BASE/api/ui/rule_overrides_save_v2" -H 'Content-Type: application/json' -d '{"data":{"rules":[]}}' | sed -n '1,14p'
echo
RID="$(curl -fsS "$BASE/api/ui/runs_v2?limit=1" | python3 -c 'import sys,json; print(json.load(sys.stdin)["items"][0]["rid"])')"
curl -sS -i "$BASE/api/ui/rule_overrides_apply_v2?rid=$RID" -H 'Content-Type: application/json' -d '{"data":{"rules":[]}}' | sed -n '1,16p'
echo
echo "[DONE] api/ui POST handlers installed"
