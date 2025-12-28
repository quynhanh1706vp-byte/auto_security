#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need rg; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ruleovr_replace_${TS}"
echo "[BACKUP] ${APP}.bak_ruleovr_replace_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RULE_OVERRIDES_HANDLER_REPLACED_V4"
if MARK in s:
    print("[OK] already replaced")
    raise SystemExit(0)

# Find an existing route block for either endpoint
# We will replace the FIRST matching handler block to avoid duplicate conflicts.
pat = re.compile(
    r'(?ms)^([ \t]*)@app\.route\(\s*[\'"](/api/(?:vsp/rule_overrides_v1|ui/rule_overrides_v2))[\'"][^\n]*\)\s*\n'
    r'(?:\1@app\.route\([^\n]*\)\s*\n)*'
    r'\1def\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*:\s*\n'
)
m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find existing rule_overrides route to replace. Aborting safely.")

indent = m.group(1)
fn_name = m.group(3)
start = m.start()

# Determine end of function block: next decorator/def at same indent, or EOF
tail = s[m.end():]
m_end = re.search(r'(?m)^(%s)(@app\.route\(|def\s+)[^\n]*\n' % re.escape(indent), tail)
end = m.end() + (m_end.start() if m_end else len(tail))

replacement = f"""{indent}# ===================== {MARK} =====================
{indent}# Commercial contract: GET/PUT, ro_mode, persist + audit.
{indent}def {fn_name}():
{indent}    from flask import request, jsonify
{indent}    import os, json, time
{indent}    from pathlib import Path

{indent}    OUT_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci")
{indent}    OVR_FILE = OUT_DIR / "rule_overrides_v1.json"
{indent}    AUDIT_FILE = OUT_DIR / "rule_overrides_audit.log"

{indent}    def ro_mode() -> bool:
{indent}        v = (os.environ.get("VSP_RO_MODE", "0") or "0").strip().lower()
{indent}        return v in ("1","true","yes","on")

{indent}    def load_data():
{indent}        try:
{indent}            if OVR_FILE.is_file():
{indent}                j = json.loads(OVR_FILE.read_text(encoding="utf-8", errors="replace") or "{{}}")
{indent}                if isinstance(j, dict):
{indent}                    j.setdefault("version", 1)
{indent}                    j.setdefault("items", [])
{indent}                    return j
{indent}        except Exception:
{indent}            pass
{indent}        return {{"version": 1, "updated_at": None, "items": []}}

{indent}    def audit(event: str, extra=None):
{indent}        try:
{indent}            OUT_DIR.mkdir(parents=True, exist_ok=True)
{indent}            rec = {{
{indent}                "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
{indent}                "event": event,
{indent}                "ro_mode": ro_mode(),
{indent}                "ip": request.headers.get("X-Forwarded-For","").split(",")[0].strip(),
{indent}                "ua": request.headers.get("User-Agent",""),
{indent}            }}
{indent}            if isinstance(extra, dict):
{indent}                rec.update(extra)
{indent}            with AUDIT_FILE.open("a", encoding="utf-8") as fp:
{indent}                fp.write(json.dumps(rec, ensure_ascii=False) + "\\n")
{indent}        except Exception:
{indent}            pass

{indent}    def validate(payload):
{indent}        if not isinstance(payload, dict):
{indent}            return False, "payload_not_object"
{indent}        items = payload.get("items", [])
{indent}        if items is None:
{indent}            payload["items"] = []
{indent}            return True, None
{indent}        if not isinstance(items, list):
{indent}            return False, "items_not_list"
{indent}        if any(not isinstance(x, dict) for x in items):
{indent}            return False, "items_contains_non_object"
{indent}        return True, None

{indent}    def save(payload: dict):
{indent}        OUT_DIR.mkdir(parents=True, exist_ok=True)
{indent}        tmp = OVR_FILE.with_suffix(".json.tmp")
{indent}        payload = dict(payload or {{}})
{indent}        payload.setdefault("version", 1)
{indent}        payload["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
{indent}        tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
{indent}        tmp.replace(OVR_FILE)

{indent}    if request.method == "GET":
{indent}        data = load_data()
{indent}        audit("get_rule_overrides", {{"items_len": len(data.get("items") or [])}})
{indent}        return jsonify({{"ok": True, "ro_mode": ro_mode(), "data": data}})

{indent}    # PUT
{indent}    if ro_mode():
{indent}        audit("put_rule_overrides_denied_ro_mode")
{indent}        return jsonify({{"ok": False, "error": "ro_mode", "msg": "Read-only mode enabled"}}), 403

{indent}    payload = request.get_json(silent=True)
{indent}    ok, err = validate(payload)
{indent}    if not ok:
{indent}        audit("put_rule_overrides_rejected", {{"reason": err}})
{indent}        return jsonify({{"ok": False, "error": "invalid_payload", "reason": err}}), 400

{indent}    save(payload)
{indent}    audit("put_rule_overrides_ok", {{"items_len": len((payload or {{}}).get("items") or [])}})
{indent}    return jsonify({{"ok": True, "saved": True, "ro_mode": ro_mode()}})
{indent}# =================== /{MARK} ======================
"""

# Replace only the function body region; keep decorators above intact.
s2 = s[:m.end()] + replacement + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced handler:", fn_name)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "[OK] restart service (hard fail if cannot restart)"
sudo -v
if ! sudo systemctl restart "$SVC"; then
  echo "[FAIL] restart failed; showing status+journal (tail)"
  sudo systemctl status "$SVC" --no-pager -l || true
  sudo journalctl -xeu "$SVC" --no-pager | tail -n 120 || true
  exit 2
fi

# wait health up
for i in $(seq 1 30); do
  if curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1; then break; fi
  sleep 0.3
done

echo "== [SELFTEST] GET =="
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | jq '.ok,.ro_mode, (.ro_mode|type), (.data.items|length)'

echo "== [SELFTEST] PUT sample =="
cat >/tmp/vsp_rule_ovr_sample.json <<'JSON'
{"version":1,"items":[{"id":"demo_disable_rule","enabled":false,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
JSON
code="$(curl -s -o /tmp/vsp_rule_ovr_put.out -w '%{http_code}' -X PUT \
  -H 'Content-Type: application/json' --data-binary @/tmp/vsp_rule_ovr_sample.json \
  "$BASE/api/vsp/rule_overrides_v1" || true)"
echo "PUT http_code=$code"
cat /tmp/vsp_rule_ovr_put.out | head -c 500; echo

echo "== [FILES] =="
ls -la /home/test/Data/SECURITY_BUNDLE/ui/out_ci | rg "rule_overrides" || true
test -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log && tail -n 3 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log || true

echo "[DONE] open: $BASE/rule_overrides"
