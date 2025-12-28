#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
WSGI="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need rg; need head; need ls

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

[ -f "$APP" ] || err "missing $APP"
[ -f "$WSGI" ] || err "missing $WSGI"

TS="$(date +%Y%m%d_%H%M%S)"

# ---------------------------
# (0) Restore vsp_demo_app.py to a known-good backup (fix gunicorn start)
# Prefer the latest hybrid_v6b/v6/v5_before backups (these compiled OK earlier)
# ---------------------------
bak="$(ls -1t \
  ${APP}.bak_ruleovr_hybrid_v6b_* \
  ${APP}.bak_ruleovr_hybrid_v6_* \
  ${APP}.bak_ruleovr_v5_before_* \
  ${APP}.bak_rescue_before_patch_* \
  2>/dev/null | head -n 1 || true)"

if [ -n "${bak:-}" ]; then
  cp -f "$bak" "$APP"
  ok "restored $APP from $bak"
else
  warn "no suitable backup found to restore $APP (continuing)"
fi

python3 -m py_compile "$APP" || err "vsp_demo_app.py still not compilable after restore"

# ---------------------------
# (1) Patch WSGI gateway to override /api/ui/rule_overrides_v2 and persist/audit
# ---------------------------
cp -f "$WSGI" "${WSGI}.bak_ruleovr_wsgi_v8_${TS}"
ok "backup: ${WSGI}.bak_ruleovr_wsgi_v8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RULE_OVERRIDES_WSGI_PERSIST_AUDIT_V8"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

patch = r'''
# ===================== VSP_P1_RULE_OVERRIDES_WSGI_PERSIST_AUDIT_V8 =====================
# Forcebind /api/ui/rule_overrides_v2 to a real persist+audit handler (remove feature-gapb stub).
def _vsp_rule_overrides_v2_persist_v8():
    from flask import request, jsonify
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
                "ip": request.headers.get("X-Forwarded-For","").split(",")[0].strip(),
                "ua": request.headers.get("User-Agent",""),
            }
            if isinstance(extra, dict):
                rec.update(extra)
            with AUDIT_FILE.open("a", encoding="utf-8") as fp:
                fp.write(json.dumps(rec, ensure_ascii=False) + "\n")
        except Exception:
            pass

    def load_state():
        try:
            if OVR_FILE.is_file():
                j = json.loads(OVR_FILE.read_text(encoding="utf-8", errors="replace") or "{}")
                if isinstance(j, dict):
                    rules = j.get("rules")
                    if isinstance(rules, list):
                        rules = [x for x in rules if isinstance(x, dict)]
                        j["rules"] = rules
                        j.setdefault("schema","rules_v1")
                        j.setdefault("version",1)
                        j.setdefault("updated_at", None)
                        return j, rules
        except Exception:
            pass
        return {"schema":"rules_v1","version":1,"updated_at":None,"rules":[]}, []

    def save_state(rules: list, version: int = 1):
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        tmp = OVR_FILE.with_suffix(".json.tmp")
        st = {
            "schema": "rules_v1",
            "version": int(version or 1),
            "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "rules": rules,
        }
        tmp.write_text(json.dumps(st, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(OVR_FILE)
        return st

    def normalize(payload):
        if not isinstance(payload, dict):
            return None, "payload_not_object"
        # UI common:
        if isinstance(payload.get("rules"), list):
            rules = payload.get("rules")
        # UI alt:
        elif isinstance((payload.get("data") or {}).get("rules"), list):
            rules = (payload.get("data") or {}).get("rules")
        # alt contracts we used earlier:
        elif isinstance(payload.get("items"), list):
            rules = payload.get("items")
        elif isinstance((payload.get("data") or {}).get("items"), list):
            rules = (payload.get("data") or {}).get("items")
        else:
            return None, "missing_rules"
        if any(not isinstance(x, dict) for x in rules):
            return None, "rules_contains_non_object"
        return rules, None

    if request.method == "GET":
        st, rules = load_state()
        audit("get_rule_overrides_v2", {"rules_len": len(rules)})
        return jsonify({
            "ok": True,
            "degraded": False,
            "ro_mode": ro_mode(),
            "schema": "rules_v1",
            "rules": rules,
            # extra fields for API tooling
            "items": rules,
            "data": {"version": st.get("version",1), "updated_at": st.get("updated_at"), "items": rules},
        })

    # POST/PUT
    if ro_mode():
        audit("put_rule_overrides_v2_denied_ro_mode")
        return jsonify({"ok": False, "error": "ro_mode", "msg": "Read-only mode enabled", "ro_mode": True, "schema":"rules_v1", "rules":[]}), 403

    payload = request.get_json(silent=True)
    rules, e = normalize(payload)
    if e:
        audit("put_rule_overrides_v2_rejected", {"reason": e})
        return jsonify({"ok": False, "error":"invalid_payload", "reason": e}), 400

    st = save_state(rules, version=(payload or {}).get("version", 1))
    audit("put_rule_overrides_v2_ok", {"rules_len": len(rules)})
    return jsonify({
        "ok": True,
        "saved": True,
        "degraded": False,
        "ro_mode": ro_mode(),
        "schema": "rules_v1",
        "rules": rules,
        "items": rules,
        "data": {"version": st.get("version",1), "updated_at": st.get("updated_at"), "items": rules},
    })

def _vsp_forcebind_rule_overrides_v2_v8():
    # Prefer existing helper if present; otherwise add_url_rule best-effort.
    app = globals().get("_app_real") or globals().get("app") or globals().get("application")
    if app is None:
        return False
    methods=("GET","POST","PUT")
    if "_vsp_forcebind_rule" in globals():
        try:
            globals()["_vsp_forcebind_rule"](app, "/api/ui/rule_overrides_v2", _vsp_rule_overrides_v2_persist_v8, methods=methods)
            return True
        except Exception:
            pass
    # fallback: try to remove old rule(s) then bind
    try:
        to_remove=[]
        for r in list(app.url_map.iter_rules()):
            if r.rule == "/api/ui/rule_overrides_v2":
                to_remove.append(r)
        for r in to_remove:
            try:
                app.url_map._rules.remove(r)
            except Exception:
                pass
            try:
                app.url_map._rules_by_endpoint.get(r.endpoint, []).remove(r)
            except Exception:
                pass
        app.add_url_rule("/api/ui/rule_overrides_v2", "vsp_rule_overrides_v2_persist_v8", _vsp_rule_overrides_v2_persist_v8, methods=list(methods))
        return True
    except Exception:
        return False

try:
    _ok = _vsp_forcebind_rule_overrides_v2_v8()
    # optional marker
    globals()["__VSP_RULE_OVR_V8_BINDED"] = bool(_ok)
except Exception:
    globals()["__VSP_RULE_OVR_V8_BINDED"] = False
# =================== /VSP_P1_RULE_OVERRIDES_WSGI_PERSIST_AUDIT_V8 =====================
'''.strip("\n") + "\n"

# append patch near end (safe)
s2 = s + "\n\n" + patch
p.write_text(s2, encoding="utf-8")
print("[OK] appended WSGI patch block:", MARK)
PY

python3 -m py_compile "$WSGI" || err "wsgi_vsp_ui_gateway.py not compilable after patch"

# ---------------------------
# (2) Restart service + show real crash if still failing
# ---------------------------
ok "restart service"
sudo -v
if ! sudo systemctl restart "$SVC"; then
  echo "[FAIL] restart failed; show gunicorn error log tail + journal tail"
  echo "== tail ui_8910.error.log =="
  tail -n 120 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null || true
  echo "== journalctl tail =="
  sudo journalctl -xeu "$SVC" --no-pager | tail -n 180 || true
  exit 2
fi

# wait up
for i in $(seq 1 40); do
  curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1 && break
  sleep 0.25
done

# ---------------------------
# (3) Selftest: must NOT show feature-gapb anymore
# ---------------------------
echo "== [SELFTEST] GET /api/ui/rule_overrides_v2 =="
curl -fsS "$BASE/api/ui/rule_overrides_v2" | head -c 600; echo

echo "== [SELFTEST] PUT (UI rules) =="
cat >/tmp/vsp_rule_ovr_rules.json <<'JSON'
{"rules":[{"id":"demo_disable_rule","enabled":false,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
JSON
code="$(curl -s -o /tmp/vsp_rule_ovr_put.out -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' --data-binary @/tmp/vsp_rule_ovr_rules.json \
  "$BASE/api/ui/rule_overrides_v2" || true)"
echo "POST http_code=$code"
head -c 600 /tmp/vsp_rule_ovr_put.out; echo

echo "== [FILES] =="
ls -la /home/test/Data/SECURITY_BUNDLE/ui/out_ci | grep -E 'rule_overrides_(v1\.json|audit\.log)' || true
test -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log && tail -n 3 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log || true

ok "Hard refresh UI: $BASE/rule_overrides (Ctrl+Shift+R)"
