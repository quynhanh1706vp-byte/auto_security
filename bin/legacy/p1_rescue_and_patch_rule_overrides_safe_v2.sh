#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need sort; need head; need date; need curl

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

# 0) restore newest backup made by the failed patch
bak="$(ls -1t ${APP}.bak_rule_overrides_* 2>/dev/null | head -n 1 || true)"
if [ -z "${bak:-}" ]; then
  echo "[ERR] no backup found: ${APP}.bak_rule_overrides_*"
  exit 2
fi
cp -f "$bak" "$APP"
echo "[OK] restored: $bak -> $APP"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_rescue_before_patch_${TS}"
echo "[BACKUP] ${APP}.bak_rescue_before_patch_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

APP=Path("vsp_demo_app.py")
s=APP.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_RULE_OVERRIDES_PERSIST_AUDIT_RO_MODE_V2"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

BLOCK = r'''
# ===================== VSP_P1_RULE_OVERRIDES_PERSIST_AUDIT_RO_MODE_V2 =====================
from pathlib import Path as _Path

def _vsp_ro_mode_v2() -> bool:
    import os
    v = (os.environ.get("VSP_RO_MODE", "0") or "0").strip().lower()
    return v in ("1","true","yes","on")

def _vsp_rule_ovr_paths_v2():
    out_dir = _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci")
    return out_dir, (out_dir / "rule_overrides_v1.json"), (out_dir / "rule_overrides_audit.log")

def _vsp_rule_ovr_default_v2():
    return {"version": 1, "updated_at": None, "items": []}

def _vsp_rule_ovr_load_v2():
    import json
    out_dir, f, _ = _vsp_rule_ovr_paths_v2()
    try:
        if f.is_file():
            j = json.loads(f.read_text(encoding="utf-8", errors="replace") or "{}")
            if isinstance(j, dict):
                j.setdefault("version", 1)
                j.setdefault("items", [])
                return j
    except Exception:
        pass
    return _vsp_rule_ovr_default_v2()

def _vsp_rule_ovr_audit_v2(req, event: str, extra: dict | None = None):
    import json, time
    out_dir, _, audit = _vsp_rule_ovr_paths_v2()
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
        rec = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "event": event,
            "ro_mode": _vsp_ro_mode_v2(),
            "ip": (req.headers.get("X-Forwarded-For","").split(",")[0].strip() if req else ""),
            "ua": (req.headers.get("User-Agent","") if req else ""),
        }
        if extra and isinstance(extra, dict):
            rec.update(extra)
        with audit.open("a", encoding="utf-8") as fp:
            fp.write(json.dumps(rec, ensure_ascii=False) + "\n")
    except Exception:
        pass

def _vsp_rule_ovr_validate_v2(payload):
    if not isinstance(payload, dict):
        return False, "payload_not_object"
    items = payload.get("items", [])
    if items is None:
        payload["items"] = []
        return True, None
    if not isinstance(items, list):
        return False, "items_not_list"
    if any(not isinstance(x, dict) for x in items):
        return False, "items_contains_non_object"
    return True, None

def _vsp_rule_ovr_save_v2(payload: dict):
    import json, time
    out_dir, f, _ = _vsp_rule_ovr_paths_v2()
    out_dir.mkdir(parents=True, exist_ok=True)
    tmp = f.with_suffix(".json.tmp")
    payload = dict(payload or {})
    payload.setdefault("version", 1)
    payload["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(f)

@app.route("/api/vsp/rule_overrides_v1", methods=["GET","PUT"])
@app.route("/api/ui/rule_overrides_v2", methods=["GET","PUT"])
def vsp_rule_overrides_v1():
    # local imports to avoid top-level dependency surprises
    from flask import request, jsonify

    if request.method == "GET":
        data = _vsp_rule_ovr_load_v2()
        _vsp_rule_ovr_audit_v2(request, "get_rule_overrides", {"items_len": len(data.get("items") or [])})
        return jsonify({"ok": True, "ro_mode": _vsp_ro_mode_v2(), "data": data})

    if _vsp_ro_mode_v2():
        _vsp_rule_ovr_audit_v2(request, "put_rule_overrides_denied_ro_mode")
        return jsonify({"ok": False, "error": "ro_mode", "msg": "Read-only mode enabled"}), 403

    payload = request.get_json(silent=True)
    ok, err = _vsp_rule_ovr_validate_v2(payload)
    if not ok:
        _vsp_rule_ovr_audit_v2(request, "put_rule_overrides_rejected", {"reason": err})
        return jsonify({"ok": False, "error": "invalid_payload", "reason": err}), 400

    _vsp_rule_ovr_save_v2(payload)
    _vsp_rule_ovr_audit_v2(request, "put_rule_overrides_ok", {"items_len": len((payload or {}).get("items") or [])})
    return jsonify({"ok": True, "saved": True, "ro_mode": _vsp_ro_mode_v2()})
# =================== /VSP_P1_RULE_OVERRIDES_PERSIST_AUDIT_RO_MODE_V2 ======================
'''

def find_end_of_flask_call(text: str, start_idx: int) -> int | None:
    # start_idx points somewhere on line containing "app = Flask"
    # find first '(' after 'Flask'
    m = re.search(r'Flask\s*\(', text[start_idx:])
    if not m:
        return None
    i = start_idx + m.end() - 1  # at '('
    depth = 0
    in_s = None
    esc = False
    while i < len(text):
        ch = text[i]
        if in_s:
            if esc:
                esc = False
            elif ch == '\\':
                esc = True
            elif ch == in_s:
                in_s = None
            i += 1
            continue
        else:
            if ch in ('"', "'"):
                # handle triple quotes crudely
                if text[i:i+3] == ch*3:
                    q = ch*3
                    j = text.find(q, i+3)
                    if j == -1:
                        return None
                    i = j+3
                    continue
                in_s = ch
                i += 1
                continue
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    # move to end of line
                    nl = text.find("\n", i)
                    return (nl+1) if nl != -1 else (i+1)
            i += 1
    return None

# Prefer patching inside create_app(), otherwise global app
create_m = re.search(r'(?m)^(?P<indent>[ \t]*)def\s+create_app\s*\(', s)
patched = False

def insert_block_at(pos: int, indent: str = ""):
    nonlocal s, patched
    b = "\n".join((indent + ln if ln.strip() else ln) for ln in BLOCK.splitlines())
    s = s[:pos] + b + "\n" + s[pos:]
    patched = True

if create_m:
    # search for "app = Flask" after create_app start
    tail = s[create_m.end():]
    app_m = re.search(r'(?m)^[ \t]*app\s*=\s*Flask\s*\(', tail)
    if app_m:
        app_line_start = create_m.end() + app_m.start()
        endpos = find_end_of_flask_call(s, app_line_start)
        if endpos is not None:
            # indent = the indentation of "app = Flask" line (inside create_app)
            indent = re.match(r'(?m)^([ \t]*)app\s*=\s*Flask', s[app_line_start:]).group(1)
            insert_block_at(endpos, indent=indent)
else:
    app_m = re.search(r'(?m)^[ \t]*app\s*=\s*Flask\s*\(', s)
    if app_m:
        app_line_start = app_m.start()
        endpos = find_end_of_flask_call(s, app_line_start)
        if endpos is not None:
            indent = re.match(r'(?m)^([ \t]*)app\s*=\s*Flask', s[app_line_start:]).group(1)
            insert_block_at(endpos, indent=indent)

if not patched:
    raise SystemExit("[ERR] cannot locate full 'app = Flask(...)' statement end; abort to avoid breaking file.")

APP.write_text(s, encoding="utf-8")
print("[OK] patched safely:", APP)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "[OK] restart service"
sudo -v || true
sudo systemctl restart "$SVC" || true

echo "== [SELFTEST] Rule Overrides GET =="
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"ro_mode=",j.get("ro_mode"),"items_len=",len((j.get("data") or {}).get("items") or []))'

echo "== [SELFTEST] PUT sample =="
python3 - <<'PY' >/tmp/vsp_rule_ovr_sample.json
import json
print(json.dumps({"version":1,"items":[{"id":"demo_disable_rule","enabled":False,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}))
PY

code="$(curl -s -o /tmp/vsp_rule_ovr_put.out -w '%{http_code}' -X PUT \
  -H 'Content-Type: application/json' --data-binary @/tmp/vsp_rule_ovr_sample.json \
  "$BASE/api/vsp/rule_overrides_v1" || true)"
echo "PUT http_code=$code"
head -c 400 /tmp/vsp_rule_ovr_put.out; echo

echo "[DONE] open: $BASE/rule_overrides"
