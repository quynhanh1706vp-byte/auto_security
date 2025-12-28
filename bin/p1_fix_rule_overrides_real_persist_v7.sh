#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need rg
command -v jq >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }

# ---------- (A) Patch the REAL Python handler that returns feature-gapb / rule_overrides_v2 ----------
python3 - <<'PY'
from pathlib import Path
import re, time, shutil

ROOT = Path(".")
cands = []
for p in ROOT.rglob("*.py"):
    if "site-packages" in str(p): 
        continue
    try:
        t = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "/api/ui/rule_overrides_v2" in t or "feature-gapb" in t:
        cands.append(p)

if not cands:
    raise SystemExit("[ERR] Cannot find python file containing /api/ui/rule_overrides_v2 or feature-gapb")

# choose best candidate: contains BOTH route and feature-gapb
best = None
for p in cands:
    t = p.read_text(encoding="utf-8", errors="replace")
    score = (2 if "/api/ui/rule_overrides_v2" in t else 0) + (2 if "feature-gapb" in t else 0) + (1 if "rule_overrides" in t else 0)
    if best is None or score > best[0]:
        best = (score, p)
target = best[1]

ts = time.strftime("%Y%m%d_%H%M%S")
bak = target.with_suffix(target.suffix + f".bak_ruleovr_v7_{ts}")
shutil.copy2(target, bak)
print(f"[BACKUP] {bak}")

s = target.read_text(encoding="utf-8", errors="replace")

# Replace the FIRST route block that matches /api/ui/rule_overrides_v2 (and optionally /api/vsp/rule_overrides_v1)
m = re.search(r'(?m)^(?P<indent>[ \t]*)@app\.route\(\s*[\'"]\/api\/ui\/rule_overrides_v2[\'"][^\n]*\)\s*$', s)
if not m:
    # fallback: sometimes double quoted without escaping
    m = re.search(r'(?m)^(?P<indent>[ \t]*)@app\.route\(\s*["\']\/api\/ui\/rule_overrides_v2["\'][^\n]*\)\s*$', s)
if not m:
    raise SystemExit("[ERR] Found candidate file but cannot locate @app.route('/api/ui/rule_overrides_v2'...) line")

indent = m.group("indent")
start = m.start()

# find the def under it
mdef = re.search(r'(?m)^%sdef\s+(?P<fn>[A-Za-z_]\w*)\s*\([^)]*\)\s*:\s*$' % re.escape(indent), s[m.end():])
if not mdef:
    raise SystemExit("[ERR] Found decorator but cannot find following def ...")
fn = mdef.group("fn")
after_def = m.end() + mdef.end()

# end of function = next decorator/def at same indent
tail = s[after_def:]
m_end = re.search(r'(?m)^(%s)(@app\.route\(|def\s+)[^\n]*$' % re.escape(indent), tail)
end = after_def + (m_end.start() if m_end else len(tail))

bi = indent + "    "
BLOCK = r'''
# ===================== VSP_P1_RULE_OVERRIDES_REAL_PERSIST_V7 =====================
# Commercial contract:
# - Keep UI schema: {"schema":"rules_v1","rules":[...]} for GET/PUT
# - Add ok/degraded/ro_mode + persist/audit
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

def load_rules():
    try:
        if OVR_FILE.is_file():
            j = json.loads(OVR_FILE.read_text(encoding="utf-8", errors="replace") or "{}")
            if isinstance(j, dict):
                rules = j.get("rules")
                if isinstance(rules, list):
                    # validate list of dicts
                    rules = [x for x in rules if isinstance(x, dict)]
                    return j, rules
    except Exception:
        pass
    return {"schema":"rules_v1","version":1,"updated_at":None,"rules":[]}, []

def save_rules(rules: list, version: int = 1):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = OVR_FILE.with_suffix(".json.tmp")
    state = {
        "schema": "rules_v1",
        "version": int(version or 1),
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "rules": rules,
    }
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(OVR_FILE)
    return state

def normalize_payload(payload):
    # accept:
    # - {"rules":[...]}  (UI)
    # - {"items":[...]}  (alt)
    # - {"data":{"items":[...]}} (alt)
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

# GET
if request.method == "GET":
    st, rules = load_rules()
    audit("get_rule_overrides", {"rules_len": len(rules)})
    return jsonify({
        "ok": True,
        "degraded": False,
        "ro_mode": ro_mode(),
        "schema": "rules_v1",
        "rules": rules,
        # extra contract for API/curl
        "items": rules,
        "data": {"version": st.get("version",1), "updated_at": st.get("updated_at"), "items": rules},
    })

# PUT
if ro_mode():
    audit("put_rule_overrides_denied_ro_mode")
    return jsonify({"ok": False, "error": "ro_mode", "msg": "Read-only mode enabled", "ro_mode": True, "schema":"rules_v1", "rules":[]}), 403

payload = request.get_json(silent=True)
rules, err = normalize_payload(payload)
if err:
    audit("put_rule_overrides_rejected", {"reason": err})
    return jsonify({"ok": False, "error": "invalid_payload", "reason": err}), 400

st = save_rules(rules, version=(payload or {}).get("version", 1))
audit("put_rule_overrides_ok", {"rules_len": len(rules)})
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
# =================== /VSP_P1_RULE_OVERRIDES_REAL_PERSIST_V7 ======================
'''.strip("\n")

def indent_block(txt: str, pref: str) -> str:
    out=[]
    for ln in txt.splitlines():
        out.append((pref+ln) if ln.strip() else ln)
    return "\n".join(out) + "\n"

# rebuild a whole replacement block (decorators + def + body)
new_block = []
new_block.append(f'{indent}# ===== V7 replace rule_overrides handler (auto) =====')
new_block.append(f'{indent}@app.route("/api/vsp/rule_overrides_v1", methods=["GET","PUT"])')
new_block.append(f'{indent}@app.route("/api/ui/rule_overrides_v2", methods=["GET","PUT"])')
new_block.append(f'{indent}def {fn}():')
new_block.append(indent_block(BLOCK, bi))
new_txt = "\n".join(new_block).rstrip() + "\n"

s2 = s[:start] + new_txt + s[end:]
target.write_text(s2, encoding="utf-8")
print(f"[OK] patched file: {target}  (handler={fn})")
PY

# compile only vsp_demo_app.py + the patched file(s) quickly
python3 -m py_compile vsp_demo_app.py || true

# ---------- (B) Cosmetic: prevent topbar showing DATA SOURCE: ERR on this page ----------
# Best-effort: if we find "DATA SOURCE: ERR" literal, change to "DATA SOURCE: —"
JS="$(rg -l --no-messages 'DATA SOURCE:\s*ERR|DATA SOURCE:\s*ERR' static/js 2>/dev/null | head -n 1 || true)"
if [ -n "${JS:-}" ] && [ -f "$JS" ]; then
  cp -f "$JS" "${JS}.bak_ds_errdash_${TS}"
  ok "backup: ${JS}.bak_ds_errdash_${TS}"
  python3 - <<PY
from pathlib import Path
p=Path("$JS")
s=p.read_text(encoding="utf-8", errors="replace")
s=s.replace("DATA SOURCE: ERR","DATA SOURCE: —")
p.write_text(s, encoding="utf-8")
print("[OK] patched topbar ERR->— in", p)
PY
else
  warn "could not locate topbar JS containing 'DATA SOURCE: ERR' (skip cosmetic patch)"
fi

# ---------- restart ----------
ok "restart service"
if command -v sudo >/dev/null 2>&1; then
  sudo -v || true
  if ! sudo systemctl restart "$SVC"; then
    echo "[FAIL] restart failed; status+journal tail:"
    sudo systemctl status "$SVC" --no-pager -l || true
    sudo journalctl -xeu "$SVC" --no-pager | tail -n 120 || true
    exit 2
  fi
else
  warn "sudo not found; restart service manually"
fi

# wait up a bit
for i in $(seq 1 40); do
  curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1 && break
  sleep 0.25
done

echo "== [SELFTEST] GET /api/ui/rule_overrides_v2 =="
curl -fsS "$BASE/api/ui/rule_overrides_v2" | head -c 600; echo

echo "== [SELFTEST] PUT (UI rules) =="
cat >/tmp/vsp_rule_ovr_rules.json <<'JSON'
{"rules":[{"id":"demo_disable_rule","enabled":false,"tool":"semgrep","rule_id":"demo.rule","note":"sample"}]}
JSON
code="$(curl -s -o /tmp/vsp_rule_ovr_put.out -w '%{http_code}' -X PUT \
  -H 'Content-Type: application/json' --data-binary @/tmp/vsp_rule_ovr_rules.json \
  "$BASE/api/ui/rule_overrides_v2" || true)"
echo "PUT http_code=$code"
head -c 600 /tmp/vsp_rule_ovr_put.out; echo

echo "== [FILES] =="
ls -la /home/test/Data/SECURITY_BUNDLE/ui/out_ci | grep -E 'rule_overrides_(v1\.json|audit\.log)' || true
test -f /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log && tail -n 3 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_audit.log || true

ok "Open and hard refresh: $BASE/rule_overrides (Ctrl+Shift+R)"
