#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need rg; need curl; need jq

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ruleovr_hybrid_v6_${TS}"
echo "[BACKUP] ${APP}.bak_ruleovr_hybrid_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RULE_OVERRIDES_HYBRID_PERSIST_AUDIT_RO_MODE_V6"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# locate function definition (keep decorators as-is)
m = re.search(r'(?m)^(?P<indent>[ \t]*)def\s+vsp_rule_overrides_v1\s*\([^)]*\)\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find def vsp_rule_overrides_v1()")

indent = m.group("indent")
body_start = m.end()

# end of function = next def or @app.route at same indent
tail = s[body_start:]
m_end = re.search(r'(?m)^(%s)(@app\.route\(|def\s+)[^\n]*$' % re.escape(indent), tail)
body_end = body_start + (m_end.start() if m_end else len(tail))

bi = indent + "    "  # body indent

new_body = f"""
{bi}# ===================== {MARK} =====================
{bi}from flask import request, jsonify
{bi}import os, json, time
{bi}from pathlib import Path

{bi}OUT_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci")
{bi}OVR_FILE = OUT_DIR / "rule_overrides_v1.json"
{bi}AUDIT_FILE = OUT_DIR / "rule_overrides_audit.log"

{bi}def ro_mode() -> bool:
{bi}    v = (os.environ.get("VSP_RO_MODE", "0") or "0").strip().lower()
{bi}    return v in ("1","true","yes","on")

{bi}def audit(event: str, extra=None):
{bi}    try:
{bi}        OUT_DIR.mkdir(parents=True, exist_ok=True)
{bi}        rec = {{
{bi}            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
{bi}            "event": event,
{bi}            "ro_mode": ro_mode(),
{bi}            "ip": request.headers.get("X-Forwarded-For","").split(",")[0].strip(),
{bi}            "ua": request.headers.get("User-Agent",""),
{bi}        }}
{bi}        if isinstance(extra, dict):
{bi}            rec.update(extra)
{bi}        with AUDIT_FILE.open("a", encoding="utf-8") as fp:
{bi}            fp.write(json.dumps(rec, ensure_ascii=False) + "\\n")
{bi}    except Exception:
{bi}        pass

{bi}def load_state():
{bi}    # canonical internal state: version + items(list[dict])
{bi}    try:
{bi}        if OVR_FILE.is_file():
{bi}            j = json.loads(OVR_FILE.read_text(encoding="utf-8", errors="replace") or "{{}}")
{bi}            if isinstance(j, dict):
{bi}                j.setdefault("version", 1)
{bi}                j.setdefault("items", [])
{bi}                return j
{bi}    except Exception:
{bi}        pass
{bi}    return {{"version": 1, "updated_at": None, "items": []}}

{bi}def save_state(items: list, version: int = 1):
{bi}    OUT_DIR.mkdir(parents=True, exist_ok=True)
{bi}    tmp = OVR_FILE.with_suffix(".json.tmp")
{bi}    state = {{
{bi}        "version": int(version or 1),
{bi}        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
{bi}        "items": items,
{bi}    }}
{bi}    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
{bi}    tmp.replace(OVR_FILE)
{bi}    return state

{bi}def normalize_payload(payload):
{bi}    # Accept:
{bi}    #  - UI contract: {{ "rules": [...] }}
{bi}    #  - alt: {{ "items": [...] }}
{bi}    #  - alt: {{ "data": {{ "items": [...] }} }}
{bi}    if not isinstance(payload, dict):
{bi}        return None, "payload_not_object"
{bi}    if isinstance(payload.get("rules"), list):
{bi}        items = payload.get("rules")
{bi}    elif isinstance(payload.get("items"), list):
{bi}        items = payload.get("items")
{bi}    elif isinstance((payload.get("data") or {{}}).get("items"), list):
{bi}        items = (payload.get("data") or {{}}).get("items")
{bi}    else:
{bi}        # empty allowed -> treat as []
{bi}        if payload.get("rules") is None and payload.get("items") is None and payload.get("data") is None:
{bi}            items = []
{bi}        else:
{bi}            return None, "missing_rules_or_items"
{bi}    # validate list of objects
{bi}    if any(not isinstance(x, dict) for x in items):
{bi}        return None, "items_contains_non_object"
{bi}    return items, None

{bi}if request.method == "GET":
{bi}    st = load_state()
{bi}    items = st.get("items") or []
{bi}    audit("get_rule_overrides", {{"items_len": len(items)}})
{bi}    # Return hybrid: keep UI "rules", plus "items", plus canonical "data"
{bi}    return jsonify({{
{bi}        "ok": True,
{bi}        "degraded": False,
{bi}        "ro_mode": ro_mode(),
{bi}        "rules": items,
{bi}        "items": items,
{bi}        "data": st,
{bi}    }})

{bi}# PUT
{bi}if ro_mode():
{bi}    audit("put_rule_overrides_denied_ro_mode")
{bi}    return jsonify({{"ok": False, "error": "ro_mode", "msg": "Read-only mode enabled", "ro_mode": True}}), 403

{bi}payload = request.get_json(silent=True)
{bi}items, err = normalize_payload(payload)
{bi}if err:
{bi}    audit("put_rule_overrides_rejected", {{"reason": err}})
{bi}    return jsonify({{"ok": False, "error": "invalid_payload", "reason": err}}), 400

{bi}st = save_state(items, version=(payload or {{}}).get("version", 1))
{bi}audit("put_rule_overrides_ok", {{"items_len": len(items)}})
{bi}return jsonify({{
{bi}    "ok": True,
{bi}    "saved": True,
{bi}    "degraded": False,
{bi}    "ro_mode": ro_mode(),
{bi}    "rules": items,
{bi}    "items": items,
{bi}    "data": st,
{bi}})
{bi}# =================== /{MARK} ======================
""".lstrip("\n")

s2 = s[:body_start] + "\n" + new_body + "\n" + s[body_end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched body of vsp_rule_overrides_v1()")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "[OK] restart service"
sudo -v
sudo systemctl restart "$SVC"

# wait up
for i in $(seq 1 40); do
  if curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1; then break; fi
  sleep 0.25
done

echo "== [SELFTEST] GET =="
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | jq '.ok,.ro_mode, (.ro_mode|type), (.rules|length), (.items|length), (.data.items|length)'

echo "== [SELFTEST] PUT (UI-style rules) =="
cat >/tmp/vsp_rule_ovr_rules.json <<'JSON'
{"rules":[{"id":"demo_disable_rule","enabled":false,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
JSON
code="$(curl -s -o /tmp/vsp_rule_ovr_put.out -w '%{http_code}' -X PUT \
  -H 'Content-Type: application/json' --data-binary @/tmp/vsp_rule_ovr_rules.json \
  "$BASE/api/ui/rule_overrides_v2" || true)"
echo "PUT http_code=$code"
cat /tmp/vsp_rule_ovr_put.out | head -c 500; echo

echo "== [FILES] =="
ls -la /home/test/Data/SECURITY_BUNDLE/ui/out_ci | rg "rule_overrides" || true
test -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log && tail -n 3 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log || true

echo "[DONE] hard refresh UI: $BASE/rule_overrides"
