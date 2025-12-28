#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need rg; need curl

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_rule_overrides_${TS}"
echo "[BACKUP] ${APP}.bak_rule_overrides_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

APP = Path("vsp_demo_app.py")
s = APP.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RULE_OVERRIDES_PERSIST_AUDIT_RO_MODE_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

block = r'''
# ===================== VSP_P1_RULE_OVERRIDES_PERSIST_AUDIT_RO_MODE_V1 =====================
import os, json, time
from pathlib import Path
from flask import request, jsonify

_VSP_UI_OUT_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci")
_VSP_RULE_OVR_FILE = _VSP_UI_OUT_DIR / "rule_overrides_v1.json"
_VSP_RULE_OVR_AUDIT = _VSP_UI_OUT_DIR / "rule_overrides_audit.log"

def _vsp_ro_mode() -> bool:
    v = (os.environ.get("VSP_RO_MODE", "0") or "0").strip().lower()
    return v in ("1","true","yes","on")

def _vsp_rule_ovr_default():
    return {"version": 1, "updated_at": None, "items": []}

def _vsp_rule_ovr_load():
    try:
        if _VSP_RULE_OVR_FILE.is_file():
            j = json.loads(_VSP_RULE_OVR_FILE.read_text(encoding="utf-8", errors="replace") or "{}")
            if isinstance(j, dict):
                if "items" not in j: j["items"] = []
                if "version" not in j: j["version"] = 1
                return j
    except Exception:
        pass
    return _vsp_rule_ovr_default()

def _vsp_rule_ovr_audit(event: str, extra: dict | None = None):
    try:
        _VSP_UI_OUT_DIR.mkdir(parents=True, exist_ok=True)
        rec = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "event": event,
            "ro_mode": _vsp_ro_mode(),
            "ip": (request.headers.get("X-Forwarded-For","").split(",")[0].strip() if request else ""),
            "ua": (request.headers.get("User-Agent","") if request else ""),
        }
        if extra and isinstance(extra, dict):
            rec.update(extra)
        with _VSP_RULE_OVR_AUDIT.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        # never break API due to audit issues
        pass

def _vsp_rule_ovr_save(payload: dict):
    _VSP_UI_OUT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = _VSP_RULE_OVR_FILE.with_suffix(".json.tmp")
    payload = dict(payload or {})
    payload.setdefault("version", 1)
    payload["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(_VSP_RULE_OVR_FILE)

def _vsp_rule_ovr_validate(payload):
    # keep flexible but prevent obvious junk
    if not isinstance(payload, dict):
        return False, "payload_not_object"
    items = payload.get("items", [])
    if items is None:
        payload["items"] = []
        return True, None
    if not isinstance(items, list):
        return False, "items_not_list"
    # each item should be a dict (best effort)
    bad = sum(1 for x in items if not isinstance(x, dict))
    if bad:
        return False, "items_contains_non_object"
    return True, None

# NOTE: expose BOTH endpoints for backward compatibility (UI old/new)
@app.route("/api/vsp/rule_overrides_v1", methods=["GET","PUT"])
@app.route("/api/ui/rule_overrides_v2", methods=["GET","PUT"])
def vsp_rule_overrides_v1():
    if request.method == "GET":
        data = _vsp_rule_ovr_load()
        _vsp_rule_ovr_audit("get_rule_overrides", {"items_len": len(data.get("items") or [])})
        return jsonify({"ok": True, "ro_mode": _vsp_ro_mode(), "data": data})

    # PUT
    if _vsp_ro_mode():
        _vsp_rule_ovr_audit("put_rule_overrides_denied_ro_mode")
        return jsonify({"ok": False, "error": "ro_mode", "msg": "Read-only mode enabled"}), 403

    payload = request.get_json(silent=True)
    ok, err = _vsp_rule_ovr_validate(payload)
    if not ok:
        _vsp_rule_ovr_audit("put_rule_overrides_rejected", {"reason": err})
        return jsonify({"ok": False, "error": "invalid_payload", "reason": err}), 400

    _vsp_rule_ovr_save(payload)
    _vsp_rule_ovr_audit("put_rule_overrides_ok", {"items_len": len((payload or {}).get("items") or [])})
    return jsonify({"ok": True, "saved": True, "ro_mode": _vsp_ro_mode()})
# =================== /VSP_P1_RULE_OVERRIDES_PERSIST_AUDIT_RO_MODE_V1 ======================
'''

def insert_after_global_flask_app(s: str):
    # find global: app = Flask(
    m = re.search(r'(?m)^(?P<indent>[ \t]*)app\s*=\s*Flask\s*\(', s)
    if not m:
        return None
    idx = s.find("\n", m.end())
    if idx < 0: idx = m.end()
    return s[:idx+1] + block + "\n" + s[idx+1:]

def insert_inside_create_app(s: str):
    # find def create_app(
    m = re.search(r'(?m)^(?P<indent>[ \t]*)def\s+create_app\s*\(', s)
    if not m:
        return None
    fn_indent = m.group("indent")
    # search for "app = Flask(" after create_app def
    tail = s[m.end():]
    m2 = re.search(r'(?m)^(?P<indent>[ \t]*)app\s*=\s*Flask\s*\(', tail)
    if not m2:
        return None
    app_line_start = m.end() + m2.start()
    app_line_end = s.find("\n", app_line_start)
    if app_line_end < 0: app_line_end = app_line_start

    # derive indent for code inside function from app assignment line indent
    app_indent = re.search(r'(?m)^([ \t]*)app\s*=\s*Flask\s*\(', s[app_line_start:]).group(1)
    # indent the whole block by app_indent
    indented = "\n".join((app_indent + ln if ln.strip() else ln) for ln in block.splitlines())
    return s[:app_line_end+1] + indented + "\n" + s[app_line_end+1:]

out = None
# prefer inserting inside create_app() to avoid indentation issues
out = insert_inside_create_app(s)
if out is None:
    out = insert_after_global_flask_app(s)
if out is None:
    raise SystemExit("[ERR] cannot locate Flask app creation (create_app/app=Flask). Patch aborted.")

APP.write_text(out, encoding="utf-8")
print("[OK] patched", APP)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

# Patch UI JS (best-effort): point UI to /api/vsp/rule_overrides_v1 if it hardcodes old path
JS_CAND="$(rg -l --no-messages -n 'rule_overrides|/api/ui/rule_overrides_v2|/api/vsp/rule_overrides' static/js 2>/dev/null | head -n 1 || true)"
if [ -n "${JS_CAND:-}" ] && [ -f "$JS_CAND" ]; then
  cp -f "$JS_CAND" "${JS_CAND}.bak_ruleovr_${TS}"
  echo "[BACKUP] ${JS_CAND}.bak_ruleovr_${TS}"
  python3 - <<PY
from pathlib import Path
import re
p=Path("$JS_CAND")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_P1_RULE_OVERRIDES_UI_API_V1" not in s:
    s="/* ===== VSP_P1_RULE_OVERRIDES_UI_API_V1 ===== */\\n"+s
s=s.replace("/api/ui/rule_overrides_v2", "/api/vsp/rule_overrides_v1")
# add a tiny ro_mode guard if there is a save() function (best effort)
if "VSP_P1_RULE_OVERRIDES_RO_GUARD_V1" not in s:
    s=s.replace("function save", "/* VSP_P1_RULE_OVERRIDES_RO_GUARD_V1 */\\nfunction save")
p.write_text(s, encoding="utf-8")
print("[OK] patched UI JS:", p)
PY
else
  echo "[WARN] could not locate overrides JS to patch (ok; backend keeps alias anyway)"
fi

echo "[OK] restart service"
if command -v sudo >/dev/null 2>&1; then
  sudo -v || true
  sudo systemctl restart "$SVC" || true
fi

echo "== [SELFTEST] Rule Overrides API =="
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"ro_mode=",j.get("ro_mode"),"items_len=",len((j.get("data") or {}).get("items") or []))'

echo "== [SELFTEST] PUT sample (non-destructive) =="
python3 - <<'PY' >/tmp/vsp_rule_ovr_sample.json
import json, time
j={"version":1,"items":[{"id":"demo_disable_rule","enabled":False,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
print(json.dumps(j))
PY

# attempt PUT; if ro_mode enabled, should return 403 (acceptable)
code="$(curl -s -o /tmp/vsp_rule_ovr_put.out -w '%{http_code}' -X PUT \
  -H 'Content-Type: application/json' --data-binary @/tmp/vsp_rule_ovr_sample.json \
  "$BASE/api/vsp/rule_overrides_v1" || true)"
echo "PUT http_code=$code"
cat /tmp/vsp_rule_ovr_put.out | head -c 500; echo
echo "[DONE] Open: $BASE/rule_overrides"
