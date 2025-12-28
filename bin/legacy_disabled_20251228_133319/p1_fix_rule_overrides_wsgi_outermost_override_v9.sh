#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need rg; need tail

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

[ -f "$WSGI" ] || err "missing $WSGI"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_ruleovr_outer_v9_${TS}"
ok "backup: ${WSGI}.bak_ruleovr_outer_v9_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RULE_OVERRIDES_WSGI_OUTERMOST_OVERRIDE_V9"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

patch = r'''
# ===================== VSP_P1_RULE_OVERRIDES_WSGI_OUTERMOST_OVERRIDE_V9 =====================
# This middleware is outermost and overrides any earlier FORCE200 middleware for:
#   - /api/ui/rule_overrides_v2
#   - /api/vsp/rule_overrides_v1
# It persists to: /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1.json
# Audit log:     /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log

def _vsp_rule_ovr_v9_wsgi_mw(app):
    import os, json, time
    from pathlib import Path

    OUT_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci")
    OVR_FILE = OUT_DIR / "rule_overrides_v1.json"
    AUDIT_FILE = OUT_DIR / "rule_overrides_audit.log"

    def ro_mode() -> bool:
        v = (os.environ.get("VSP_RO_MODE", "0") or "0").strip().lower()
        return v in ("1","true","yes","on")

    def audit(event: str, extra=None):
        try:
            OUT_DIR.mkdir(parents=True, exist_ok=True)
            rec = {
                "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "event": event,
                "ro_mode": ro_mode(),
            }
            if isinstance(extra, dict):
                rec.update(extra)
            with AUDIT_FILE.open("a", encoding="utf-8") as fp:
                fp.write(json.dumps(rec, ensure_ascii=False) + "\n")
        except Exception:
            pass

    def load_rules():
        try:
            if OVR_FILE.is_file():
                j = json.loads(OVR_FILE.read_text(encoding="utf-8", errors="replace") or "{}")
                if isinstance(j, dict) and isinstance(j.get("rules"), list):
                    rules = [x for x in j.get("rules") if isinstance(x, dict)]
                    j["rules"] = rules
                    j.setdefault("schema","rules_v1")
                    j.setdefault("version",1)
                    j.setdefault("updated_at", None)
                    return j, rules
        except Exception:
            pass
        return {"schema":"rules_v1","version":1,"updated_at":None,"rules":[]}, []

    def save_rules(rules, version=1):
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        tmp = OVR_FILE.with_suffix(".json.tmp")
        st = {
            "schema":"rules_v1",
            "version": int(version or 1),
            "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "rules": rules,
        }
        tmp.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(OVR_FILE)
        return st

    def read_json_body(environ):
        try:
            ln = int(environ.get("CONTENT_LENGTH") or "0")
        except Exception:
            ln = 0
        if ln <= 0:
            return None
        try:
            body = environ["wsgi.input"].read(ln)  # consume
            if not body:
                return None
            return json.loads(body.decode("utf-8", errors="replace"))
        except Exception:
            return None

    def normalize(payload):
        if not isinstance(payload, dict):
            return None, "payload_not_object"
        if isinstance(payload.get("rules"), list):
            rules = payload.get("rules")
        elif isinstance(payload.get("items"), list):
            rules = payload.get("items")
        elif isinstance((payload.get("data") or {}).get("items"), list):
            rules = (payload.get("data") or {}).get("items")
        else:
            return None, "missing_rules"
        if any(not isinstance(x, dict) for x in rules):
            return None, "rules_contains_non_object"
        return rules, None

    def respond(start_response, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        status = f"{code} OK" if code == 200 else (f"{code} Forbidden" if code == 403 else f"{code} Bad Request")
        headers = [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(data))),
        ]
        start_response(status, headers)
        return [data]

    class MW:
        def __init__(self, app):
            self.app = app

        def __call__(self, environ, start_response):
            path = environ.get("PATH_INFO","") or ""
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

            if path not in ("/api/ui/rule_overrides_v2", "/api/vsp/rule_overrides_v1"):
                return self.app(environ, start_response)

            # override here
            if method == "GET":
                st, rules = load_rules()
                audit("get_rule_overrides_v9", {"path": path, "rules_len": len(rules)})
                return respond(start_response, 200, {
                    "ok": True,
                    "degraded": False,
                    "ro_mode": ro_mode(),
                    "schema": "rules_v1",
                    "rules": rules,
                    # extras for API tooling
                    "items": rules,
                    "data": {"version": st.get("version",1), "updated_at": st.get("updated_at"), "items": rules},
                })

            # POST/PUT
            if ro_mode():
                audit("put_rule_overrides_v9_denied_ro_mode", {"path": path})
                return respond(start_response, 403, {
                    "ok": False, "error":"ro_mode", "msg":"Read-only mode enabled",
                    "ro_mode": True, "schema":"rules_v1", "rules":[]
                })

            payload = read_json_body(environ)
            rules, e = normalize(payload)
            if e:
                audit("put_rule_overrides_v9_rejected", {"path": path, "reason": e})
                return respond(start_response, 400, {"ok": False, "error":"invalid_payload", "reason": e})

            st = save_rules(rules, version=(payload or {}).get("version", 1))
            audit("put_rule_overrides_v9_ok", {"path": path, "rules_len": len(rules)})
            return respond(start_response, 200, {
                "ok": True,
                "saved": True,
                "degraded": False,
                "ro_mode": ro_mode(),
                "schema": "rules_v1",
                "rules": rules,
                "items": rules,
                "data": {"version": st.get("version",1), "updated_at": st.get("updated_at"), "items": rules},
            })

    return MW(app)

# install as OUTERMOST wrapper
try:
    _app = globals().get("application") or globals().get("app") or globals().get("_application") or globals().get("_app")
    if _app is not None:
        globals()["application"] = _vsp_rule_ovr_v9_wsgi_mw(_app)
        globals()["__VSP_RULE_OVR_V9_OUTERMOST"] = True
    else:
        globals()["__VSP_RULE_OVR_V9_OUTERMOST"] = False
except Exception:
    globals()["__VSP_RULE_OVR_V9_OUTERMOST"] = False
# =================== /VSP_P1_RULE_OVERRIDES_WSGI_OUTERMOST_OVERRIDE_V9 =====================
'''.strip("\n") + "\n"

p.write_text(s + "\n\n" + patch, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$WSGI"
ok "py_compile OK"

ok "restart service"
sudo -v
sudo systemctl restart "$SVC"

# wait up
for i in $(seq 1 40); do
  curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1 && break
  sleep 0.25
done

echo "== [SELFTEST] GET =="
curl -fsS "$BASE/api/ui/rule_overrides_v2" | head -c 300; echo

echo "== [SELFTEST] POST =="
cat >/tmp/vsp_rule_ovr_rules.json <<'JSON'
{"rules":[{"id":"demo_disable_rule","enabled":false,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
JSON
code="$(curl -s -o /tmp/vsp_rule_ovr_put.out -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' --data-binary @/tmp/vsp_rule_ovr_rules.json \
  "$BASE/api/ui/rule_overrides_v2" || true)"
echo "POST http_code=$code"
head -c 300 /tmp/vsp_rule_ovr_put.out; echo

echo "== [FILES] =="
ls -la /home/test/Data/SECURITY_BUNDLE/ui/out_ci | grep -E 'rule_overrides_(v1\.json|audit\.log)' || true
test -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log && tail -n 3 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log || true

ok "Hard refresh UI: $BASE/rule_overrides (Ctrl+Shift+R)"
