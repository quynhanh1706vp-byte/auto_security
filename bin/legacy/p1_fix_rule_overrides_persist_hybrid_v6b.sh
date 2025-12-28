#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v jq >/dev/null 2>&1 || { echo "[ERR] missing jq"; exit 2; }

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ruleovr_hybrid_v6b_${TS}"
echo "[BACKUP] ${APP}.bak_ruleovr_hybrid_v6b_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RULE_OVERRIDES_HYBRID_PERSIST_AUDIT_RO_MODE_V6B"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

m = re.search(r'(?m)^(?P<indent>[ \t]*)def\s+vsp_rule_overrides_v1\s*\([^)]*\)\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find def vsp_rule_overrides_v1()")

indent = m.group("indent")
body_start = m.end()

tail = s[body_start:]
m_end = re.search(r'(?m)^(%s)(@app\.route\(|def\s+)[^\n]*$' % re.escape(indent), tail)
body_end = body_start + (m_end.start() if m_end else len(tail))

bi = indent + "    "

TEMPLATE = r'''
# ===================== VSP_P1_RULE_OVERRIDES_HYBRID_PERSIST_AUDIT_RO_MODE_V6B =====================
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
    # canonical internal state: version + items(list[dict])
    try:
        if OVR_FILE.is_file():
            j = json.loads(OVR_FILE.read_text(encoding="utf-8", errors="replace") or "{}")
            if isinstance(j, dict):
                j.setdefault("version", 1)
                j.setdefault("items", [])
                return j
    except Exception:
        pass
    return {"version": 1, "updated_at": None, "items": []}

def save_state(items: list, version: int = 1):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = OVR_FILE.with_suffix(".json.tmp")
    state = {
        "version": int(version or 1),
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "items": items,
    }
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(OVR_FILE)
    return state

def normalize_payload(payload):
    # Accept:
    #  - UI contract: { "rules": [...] }
    #  - alt: { "items": [...] }
    #  - alt: { "data": { "items": [...] } }
    if not isinstance(payload, dict):
        return None, "payload_not_object"
    if isinstance(payload.get("rules"), list):
        items = payload.get("rules")
    elif isinstance(payload.get("items"), list):
        items = payload.get("items")
    elif isinstance((payload.get("data") or {}).get("items"), list):
        items = (payload.get("data") or {}).get("items")
    else:
        # allow empty -> []
        if payload.get("rules") is None and payload.get("items") is None and payload.get("data") is None:
            items = []
        else:
            return None, "missing_rules_or_items"
    if any(not isinstance(x, dict) for x in items):
        return None, "items_contains_non_object"
    return items, None

if request.method == "GET":
    st = load_state()
    items = st.get("items") or []
    audit("get_rule_overrides", {"items_len": len(items)})
    return jsonify({
        "ok": True,
        "degraded": False,
        "ro_mode": ro_mode(),
        "rules": items,
        "items": items,
        "data": st,
    })

# PUT
if ro_mode():
    audit("put_rule_overrides_denied_ro_mode")
    return jsonify({"ok": False, "error": "ro_mode", "msg": "Read-only mode enabled", "ro_mode": True}), 403

payload = request.get_json(silent=True)
items, err = normalize_payload(payload)
if err:
    audit("put_rule_overrides_rejected", {"reason": err})
    return jsonify({"ok": False, "error": "invalid_payload", "reason": err}), 400

st = save_state(items, version=(payload or {}).get("version", 1))
audit("put_rule_overrides_ok", {"items_len": len(items)})
return jsonify({
    "ok": True,
    "saved": True,
    "degraded": False,
    "ro_mode": ro_mode(),
    "rules": items,
    "items": items,
    "data": st,
})
# =================== /VSP_P1_RULE_OVERRIDES_HYBRID_PERSIST_AUDIT_RO_MODE_V6B ======================
'''.strip("\n")

def indent_block(txt: str, prefix: str) -> str:
    out=[]
    for ln in txt.splitlines():
        out.append((prefix + ln) if ln.strip() else ln)
    return "\n".join(out) + "\n"

new_body = "\n" + indent_block(TEMPLATE, bi) + "\n"
s2 = s[:body_start] + new_body + s[body_end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched body vsp_rule_overrides_v1() with", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "[OK] restart service"
sudo -v
sudo systemctl restart "$SVC"

# wait up
for i in $(seq 1 40); do
  curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1 && break
  sleep 0.25
done

echo "== [SELFTEST] GET =="
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | jq '.ok,.ro_mode, (.ro_mode|type), (.rules|length), (.items|length), (.data.items|length)'

echo "== [SELFTEST] PUT (UI rules) =="
cat >/tmp/vsp_rule_ovr_rules.json <<'JSON'
{"rules":[{"id":"demo_disable_rule","enabled":false,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
JSON
code="$(curl -s -o /tmp/vsp_rule_ovr_put.out -w '%{http_code}' -X PUT \
  -H 'Content-Type: application/json' --data-binary @/tmp/vsp_rule_ovr_rules.json \
  "$BASE/api/ui/rule_overrides_v2" || true)"
echo "PUT http_code=$code"
cat /tmp/vsp_rule_ovr_put.out | head -c 500; echo

echo "== [FILES] =="
ls -la /home/test/Data/SECURITY_BUNDLE/ui/out_ci | grep -E 'rule_overrides_(v1\.json|audit\.log)' || true
test -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log && tail -n 3 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log || true

echo "[DONE] hard refresh: $BASE/rule_overrides"
