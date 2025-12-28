#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need head; need date; need curl; need rg

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

# 0) restore newest backup from v4 attempt (file currently broken)
bak="$(ls -1t ${APP}.bak_ruleovr_replace_* 2>/dev/null | head -n 1 || true)"
if [ -z "${bak:-}" ]; then
  echo "[ERR] no backup found: ${APP}.bak_ruleovr_replace_*"
  exit 2
fi
cp -f "$bak" "$APP"
echo "[OK] restored: $bak -> $APP"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ruleovr_v5_before_${TS}"
echo "[BACKUP] ${APP}.bak_ruleovr_v5_before_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RULE_OVERRIDES_BLOCK_REPLACED_V5"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# locate first route block for rule_overrides
# start at first decorator line matching either endpoint
m = re.search(r'(?m)^(?P<indent>[ \t]*)@app\.route\(\s*[\'"]\/api\/(?:vsp\/rule_overrides_v1|ui\/rule_overrides_v2)[\'"][^\n]*\)\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find any @app.route for rule_overrides_v1/v2")

indent = m.group("indent")
start = m.start()

# from start, find following def line (same indent)
mdef = re.search(r'(?m)^%sdef\s+(?P<fn>[A-Za-z_]\w*)\s*\([^)]*\)\s*:\s*$' % re.escape(indent), s[m.end():])
if not mdef:
    raise SystemExit("[ERR] found route decorator but cannot find def under it")
fn_name = mdef.group("fn")

# find end of function block: next decorator/def at same indent, or EOF
after_def_pos = m.end() + mdef.end()
tail = s[after_def_pos:]
m_end = re.search(r'(?m)^(%s)(@app\.route\(|def\s+)[^\n]*$' % re.escape(indent), tail)
end = after_def_pos + (m_end.start() if m_end else len(tail))

def body_lines():
    # 4-space indent relative to function line
    bi = indent + "    "
    out=[]
    out.append(f'{bi}"""Commercial Rule Overrides: persist + audit + ro_mode (GET/PUT)."""')
    out.append(f'{bi}from flask import request, jsonify')
    out.append(f'{bi}import os, json, time')
    out.append(f'{bi}from pathlib import Path')
    out.append("")
    out.append(f'{bi}OUT_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci")')
    out.append(f'{bi}OVR_FILE = OUT_DIR / "rule_overrides_v1.json"')
    out.append(f'{bi}AUDIT_FILE = OUT_DIR / "rule_overrides_audit.log"')
    out.append("")
    out.append(f'{bi}def ro_mode() -> bool:')
    out.append(f'{bi}    v = (os.environ.get("VSP_RO_MODE", "0") or "0").strip().lower()')
    out.append(f'{bi}    return v in ("1","true","yes","on")')
    out.append("")
    out.append(f'{bi}def load_data():')
    out.append(f'{bi}    try:')
    out.append(f'{bi}        if OVR_FILE.is_file():')
    out.append(f'{bi}            j = json.loads(OVR_FILE.read_text(encoding="utf-8", errors="replace") or "{{}}")')
    out.append(f'{bi}            if isinstance(j, dict):')
    out.append(f'{bi}                j.setdefault("version", 1)')
    out.append(f'{bi}                j.setdefault("items", [])')
    out.append(f'{bi}                return j')
    out.append(f'{bi}    except Exception:')
    out.append(f'{bi}        pass')
    out.append(f'{bi}    return {{"version": 1, "updated_at": None, "items": []}}')
    out.append("")
    out.append(f'{bi}def audit(event: str, extra=None):')
    out.append(f'{bi}    try:')
    out.append(f'{bi}        OUT_DIR.mkdir(parents=True, exist_ok=True)')
    out.append(f'{bi}        rec = {{')
    out.append(f'{bi}            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),')
    out.append(f'{bi}            "event": event,')
    out.append(f'{bi}            "ro_mode": ro_mode(),')
    out.append(f'{bi}            "ip": request.headers.get("X-Forwarded-For","").split(",")[0].strip(),')
    out.append(f'{bi}            "ua": request.headers.get("User-Agent",""),')
    out.append(f'{bi}        }}')
    out.append(f'{bi}        if isinstance(extra, dict):')
    out.append(f'{bi}            rec.update(extra)')
    out.append(f'{bi}        with AUDIT_FILE.open("a", encoding="utf-8") as fp:')
    out.append(f'{bi}            fp.write(json.dumps(rec, ensure_ascii=False) + "\\n")')
    out.append(f'{bi}    except Exception:')
    out.append(f'{bi}        pass')
    out.append("")
    out.append(f'{bi}def validate(payload):')
    out.append(f'{bi}    if not isinstance(payload, dict):')
    out.append(f'{bi}        return False, "payload_not_object"')
    out.append(f'{bi}    items = payload.get("items", [])')
    out.append(f'{bi}    if items is None:')
    out.append(f'{bi}        payload["items"] = []')
    out.append(f'{bi}        return True, None')
    out.append(f'{bi}    if not isinstance(items, list):')
    out.append(f'{bi}        return False, "items_not_list"')
    out.append(f'{bi}    if any(not isinstance(x, dict) for x in items):')
    out.append(f'{bi}        return False, "items_contains_non_object"')
    out.append(f'{bi}    return True, None')
    out.append("")
    out.append(f'{bi}def save(payload: dict):')
    out.append(f'{bi}    OUT_DIR.mkdir(parents=True, exist_ok=True)')
    out.append(f'{bi}    tmp = OVR_FILE.with_suffix(".json.tmp")')
    out.append(f'{bi}    payload = dict(payload or {{}})')
    out.append(f'{bi}    payload.setdefault("version", 1)')
    out.append(f'{bi}    payload["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")')
    out.append(f'{bi}    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")')
    out.append(f'{bi}    tmp.replace(OVR_FILE)')
    out.append("")
    out.append(f'{bi}if request.method == "GET":')
    out.append(f'{bi}    data = load_data()')
    out.append(f'{bi}    audit("get_rule_overrides", {{"items_len": len(data.get("items") or [])}})')
    out.append(f'{bi}    return jsonify({{"ok": True, "ro_mode": ro_mode(), "data": data}})')
    out.append("")
    out.append(f'{bi}# PUT')
    out.append(f'{bi}if ro_mode():')
    out.append(f'{bi}    audit("put_rule_overrides_denied_ro_mode")')
    out.append(f'{bi}    return jsonify({{"ok": False, "error": "ro_mode", "msg": "Read-only mode enabled"}}), 403')
    out.append("")
    out.append(f'{bi}payload = request.get_json(silent=True)')
    out.append(f'{bi}ok, err = validate(payload)')
    out.append(f'{bi}if not ok:')
    out.append(f'{bi}    audit("put_rule_overrides_rejected", {{"reason": err}})')
    out.append(f'{bi}    return jsonify({{"ok": False, "error": "invalid_payload", "reason": err}}), 400')
    out.append("")
    out.append(f'{bi}save(payload)')
    out.append(f'{bi}audit("put_rule_overrides_ok", {{"items_len": len((payload or {{}}).get("items") or [])}})')
    out.append(f'{bi}return jsonify({{"ok": True, "saved": True, "ro_mode": ro_mode()}})')
    return "\n".join(out) + "\n"

new_block = []
new_block.append(f"{indent}# ===================== {MARK} =====================")
new_block.append(f'{indent}@app.route("/api/vsp/rule_overrides_v1", methods=["GET","PUT"])')
new_block.append(f'{indent}@app.route("/api/ui/rule_overrides_v2", methods=["GET","PUT"])')
new_block.append(f"{indent}def {fn_name}():")
new_block.append(body_lines())
new_block.append(f"{indent}# =================== /{MARK} ======================")
new_block_txt = "\n".join(new_block).rstrip() + "\n"

s2 = s[:start] + new_block_txt + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced whole block for", fn_name)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "[OK] restart service (hard fail if restart fails)"
sudo -v
sudo systemctl restart "$SVC"

# wait until health is up
for i in $(seq 1 40); do
  if curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1; then break; fi
  sleep 0.25
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
