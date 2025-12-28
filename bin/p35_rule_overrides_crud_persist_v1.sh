#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p35_rulecrud_${TS}"
echo "[BACKUP] ${APP}.bak_p35_rulecrud_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P35_RULE_OVERRIDES_CRUD_PERSIST_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Ensure imports exist (safe append if missing)
need_imports = [
    ("import os", r"(?m)^\s*import\s+os\s*$"),
    ("import json", r"(?m)^\s*import\s+json\s*$"),
    ("import time", r"(?m)^\s*import\s+time\s*$"),
    ("import uuid", r"(?m)^\s*import\s+uuid\s*$"),
]
for line, pat in need_imports:
    if not re.search(pat, s):
        s = line + "\n" + s

# Flask request/jsonify may already exist; we import locally in function anyway.
# Patch the existing route /api/vsp/rule_overrides_v1 (replace handler body safely)
route_pat = re.compile(r"(?ms)^(?P<decorators>(?:@app\.route\(\s*['\"]/api/vsp/rule_overrides_v1['\"][^\)]*\)\s*\n)+)\s*def\s+(?P<fname>[A-Za-z_]\w*)\s*\([^\)]*\)\s*:\s*\n(?P<body>(?:[ \t].*\n)*)")
m = route_pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find existing @app.route('/api/vsp/rule_overrides_v1' ...) in vsp_demo_app.py")

decorators = m.group("decorators")
fname = m.group("fname")

# Ensure methods include CRUD in decorator (if not present)
# If the decorator line already has methods=..., we leave it; otherwise we add methods list.
def ensure_methods(decs: str) -> str:
    out=[]
    for line in decs.splitlines(True):
        if "@app.route(" in line and "/api/vsp/rule_overrides_v1" in line:
            if "methods=" in line:
                out.append(line)
            else:
                # add methods argument before trailing )
                line2 = line.rstrip()
                if line2.endswith(")"):
                    line2 = line2[:-1] + ", methods=['GET','POST','PUT','DELETE'])\n"
                else:
                    line2 = line + ""
                out.append(line2)
        else:
            out.append(line)
    return "".join(out)

decorators2 = ensure_methods(decorators)

new_func = f"""{decorators2}def {fname}():
    \"\"\"{MARK}
    Commercial CRUD + persist for rule overrides.
    Storage: /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1/rule_overrides.json
    Contract:
      GET  -> {{ok:true, items:[...], total:n, path:file, ts:epoch}}
      POST -> create (body: item or {{item}} or {{items:[...]}}); returns created
      PUT  -> update by id
      DELETE -> delete by id (query ?id= or json {{id}})
    \"\"\"
    try:
        from flask import request, jsonify
        import os, json, time, uuid

        ROOT = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1"
        FILE = os.path.join(ROOT, "rule_overrides.json")
        os.makedirs(ROOT, exist_ok=True)

        def _now():
            return int(time.time())

        def _load():
            try:
                if os.path.isfile(FILE):
                    with open(FILE, "r", encoding="utf-8") as f:
                        j = json.load(f)
                    items = j.get("items") if isinstance(j, dict) else None
                    if isinstance(items, list):
                        return items
                return []
            except Exception:
                return []

        def _atomic_write(items):
            tmp = FILE + ".tmp"
            data = {{
                "ok": True,
                "schema": "vsp_rule_overrides_v1",
                "updated_at": _now(),
                "items": items,
            }}
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=False)
                f.write("\\n")
            os.replace(tmp, FILE)

        def _norm_item(x):
            if not isinstance(x, dict):
                return None
            it = dict(x)
            rid = (it.get("id") or "").strip()
            if not rid:
                rid = "ro_" + uuid.uuid4().hex[:12]
            it["id"] = rid
            it.setdefault("enabled", True)
            it.setdefault("action", it.get("op") or "suppress")  # legacy 'op'
            it.setdefault("reason", it.get("note") or "")
            it["updated_at"] = _now()
            return it

        items = _load()

        if request.method == "GET":
            return jsonify({{
                "ok": True,
                "items": items,
                "total": len(items),
                "path": FILE,
                "ts": _now(),
            }})

        # Parse JSON safely
        body = None
        try:
            body = request.get_json(silent=True) or {{}}
        except Exception:
            body = {{}}

        def _bad(msg, code=200):
            return jsonify({{"ok": False, "reason": msg, "ts": _now()}}), code

        if request.method == "POST":
            cand = None
            if isinstance(body, dict) and "item" in body:
                cand = body.get("item")
            elif isinstance(body, dict) and "items" in body:
                # bulk append (commercial-friendly)
                new_items=[]
                for x in (body.get("items") or []):
                    it=_norm_item(x)
                    if it: new_items.append(it)
                if not new_items:
                    return _bad("no valid items")
                # merge by id
                byid={{i.get("id"): i for i in items if isinstance(i, dict) and i.get("id")}}
                for it in new_items:
                    byid[it["id"]] = it
                merged=list(byid.values())
                merged.sort(key=lambda z: (z.get("id") or ""))
                _atomic_write(merged)
                return jsonify({{"ok": True, "items": merged, "total": len(merged), "ts": _now()}})
            else:
                cand = body

            it = _norm_item(cand)
            if not it:
                return _bad("invalid json body")

            # upsert by id
            out=[]
            seen=False
            for x in items:
                if isinstance(x, dict) and x.get("id") == it["id"]:
                    out.append(it); seen=True
                else:
                    out.append(x)
            if not seen:
                out.append(it)
            out = [x for x in out if isinstance(x, dict)]
            out.sort(key=lambda z: (z.get("id") or ""))
            _atomic_write(out)
            return jsonify({{"ok": True, "created": it, "total": len(out), "ts": _now()}})

        if request.method == "PUT":
            it = _norm_item(body if isinstance(body, dict) else None)
            if not it or not it.get("id"):
                return _bad("missing id")

            out=[]
            found=False
            for x in items:
                if isinstance(x, dict) and x.get("id") == it["id"]:
                    out.append(it); found=True
                else:
                    out.append(x)
            if not found:
                return _bad("id not found")
            out = [x for x in out if isinstance(x, dict)]
            out.sort(key=lambda z: (z.get("id") or ""))
            _atomic_write(out)
            return jsonify({{"ok": True, "updated": it, "total": len(out), "ts": _now()}})

        if request.method == "DELETE":
            did = (request.args.get("id") or (body.get("id") if isinstance(body, dict) else "") or "").strip()
            if not did:
                return _bad("missing id")
            out=[x for x in items if not (isinstance(x, dict) and x.get("id")==did)]
            if len(out) == len(items):
                return _bad("id not found")
            out.sort(key=lambda z: (z.get("id") or ""))
            _atomic_write(out)
            return jsonify({{"ok": True, "deleted": did, "total": len(out), "ts": _now()}})

        return _bad("method not allowed", 405)

    except Exception as e:
        try:
            from flask import jsonify
            return jsonify({{"ok": False, "reason": "exception", "error": str(e), "ts": 0}}), 200
        except Exception:
            return ("{{\\"ok\\":false}}", 200, {{"Content-Type":"application/json"}})
"""

# Replace old function block
start = m.start()
end = m.end()
s = s[:start] + new_func + "\n" + s[end:]

p.write_text(s, encoding="utf-8")
print("[OK] patched route:", fname)
print("[OK] marker:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^${SVC}"; then
  echo "[INFO] restarting: $SVC"
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"
fi

echo "== [WARM] wait selfcheck_p0 =="
ok=0
for i in $(seq 1 30); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/tmp/_p35_selfcheck.json 2>/tmp/_p35_err; then
    echo "[OK] selfcheck ok (try#$i)"
    ok=1
    break
  else
    echo "[WARN] not ready (try#$i): $(tr -d '\n' </tmp/_p35_err | head -c 120)"
    sleep 0.2
  fi
done
[ "$ok" -eq 1 ] || { echo "[ERR] UI not reachable"; exit 2; }

echo "== [P35 TEST] CRUD rule_overrides_v1 =="

# 1) GET baseline
curl -fsS "$BASE/api/vsp/rule_overrides_v1" -o /tmp/_ro_get0.json
python3 - <<'PY'
import json
j=json.load(open("/tmp/_ro_get0.json","r",encoding="utf-8"))
print("[GET0] ok=", j.get("ok"), "total=", j.get("total"))
PY

# 2) POST create
RID="ro_test_$(date +%s)"
cat > /tmp/_ro_post.json <<JSON
{
  "tool": "semgrep",
  "rule_id": "TEST.P35.DEMO",
  "action": "suppress",
  "severity_override": "INFO",
  "reason": "p35 smoke",
  "enabled": true,
  "id": "$RID"
}
JSON
curl -fsS -X POST -H 'Content-Type: application/json' --data-binary @/tmp/_ro_post.json \
  "$BASE/api/vsp/rule_overrides_v1" -o /tmp/_ro_post_out.json

python3 - <<'PY'
import json
j=json.load(open("/tmp/_ro_post_out.json","r",encoding="utf-8"))
print("[POST] ok=", j.get("ok"), "total=", j.get("total"), "created_id=", (j.get("created") or {}).get("id"))
PY

# 3) GET should include it
curl -fsS "$BASE/api/vsp/rule_overrides_v1" -o /tmp/_ro_get1.json
python3 - <<'PY'
import json
j=json.load(open("/tmp/_ro_get1.json","r",encoding="utf-8"))
ids=set((x or {}).get("id") for x in (j.get("items") or []) if isinstance(x, dict))
print("[GET1] has_created=", ("'"$RID"'" in ids), "total=", j.get("total"), "path=", j.get("path"))
PY

# 4) DELETE it
curl -fsS -X DELETE "$BASE/api/vsp/rule_overrides_v1?id=$RID" -o /tmp/_ro_del.json
python3 - <<'PY'
import json
j=json.load(open("/tmp/_ro_del.json","r",encoding="utf-8"))
print("[DEL] ok=", j.get("ok"), "deleted=", j.get("deleted"), "total=", j.get("total"))
PY

# 5) GET verify removed
curl -fsS "$BASE/api/vsp/rule_overrides_v1" -o /tmp/_ro_get2.json
python3 - <<'PY'
import json
j=json.load(open("/tmp/_ro_get2.json","r",encoding="utf-8"))
ids=set((x or {}).get("id") for x in (j.get("items") or []) if isinstance(x, dict))
print("[GET2] removed_ok=", ("'"$RID"'" not in ids), "total=", j.get("total"))
PY

echo "== [FILE] persisted =="
ls -lh /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1/rule_overrides.json || true
