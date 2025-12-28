#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need awk; need grep
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl not found"; exit 2; }

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p35_routev4_${TS}"
echo "[BACKUP] ${W}.bak_p35_routev4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) Remove the problematic WSGI-intercept V3 block if present
m_bad="VSP_P35_RULE_OVERRIDES_WSGI_CRUD_PERSIST_V3"
pat_bad=re.compile(r"(?s)\n# --- "+re.escape(m_bad)+r" ---.*?\n# --- /"+re.escape(m_bad)+r" ---\n")
s2,n=pat_bad.subn("\n", s)
if n:
    print("[OK] removed bad block:", m_bad, "count=", n)
    s=s2

# 2) Patch the existing Flask route /api/vsp/rule_overrides_v1 inside THIS gateway file
MARK="VSP_P35_RULE_OVERRIDES_ROUTE_CRUD_PERSIST_V4"

route_pat = re.compile(
    r"(?ms)^"
    r"(?P<decorators>(?:@app\.route\(\s*['\"]/api/vsp/rule_overrides_v1['\"][^\)]*\)\s*\n)+)"
    r"\s*def\s+(?P<fname>[A-Za-z_]\w*)\s*\([^\)]*\)\s*:\s*\n"
    r"(?P<body>(?:[ \t].*\n)*)"
)
m = route_pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find @app.route('/api/vsp/rule_overrides_v1' ...) in wsgi_vsp_ui_gateway.py")

decorators=m.group("decorators")
fname=m.group("fname")

# Ensure decorator has methods list incl CRUD
def ensure_methods(decs: str) -> str:
    out=[]
    for line in decs.splitlines(True):
        if "@app.route(" in line and "/api/vsp/rule_overrides_v1" in line:
            if "methods=" in line:
                # if exists but missing methods, we won't parse; assume OK.
                out.append(line)
            else:
                line2=line.rstrip()
                if line2.endswith(")"):
                    line2=line2[:-1] + ", methods=['GET','POST','PUT','DELETE'])\n"
                out.append(line2)
        else:
            out.append(line)
    return "".join(out)

decorators2 = ensure_methods(decorators)

new_func = f"""{decorators2}def {fname}():
    \"\"\"{MARK}
    Commercial CRUD+persist for rule overrides at gateway route level (no WSGI application override).
    Storage: /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1/rule_overrides.json
    \"\"\"
    try:
        from flask import request, jsonify
        import os, json, time, uuid

        ROOT = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1"
        FILE = os.path.join(ROOT, "rule_overrides.json")
        os.makedirs(ROOT, exist_ok=True)

        def now(): return int(time.time())

        def load_items():
            try:
                if os.path.isfile(FILE):
                    with open(FILE, "r", encoding="utf-8") as f:
                        j = json.load(f)
                    if isinstance(j, dict) and isinstance(j.get("items"), list):
                        return [x for x in j["items"] if isinstance(x, dict)]
            except Exception:
                pass
            return []

        def write_atomic(items):
            tmp = FILE + ".tmp"
            data = {{
                "ok": True,
                "schema": "vsp_rule_overrides_v1",
                "updated_at": now(),
                "items": items,
            }}
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=False)
                f.write("\\n")
            os.replace(tmp, FILE)

        def norm_item(x):
            if not isinstance(x, dict): return None
            it = dict(x)
            rid = (it.get("id") or "").strip()
            if not rid:
                rid = "ro_" + uuid.uuid4().hex[:12]
            it["id"] = rid
            it.setdefault("enabled", True)
            it.setdefault("action", it.get("op") or "suppress")
            it.setdefault("reason", it.get("note") or "")
            it["updated_at"] = now()
            return it

        items = load_items()

        if request.method == "GET":
            return jsonify({{
                "ok": True,
                "items": items,
                "total": len(items),
                "path": FILE,
                "ts": now(),
            }})

        body = {{}}
        try:
            body = request.get_json(silent=True) or {{}}
        except Exception:
            body = {{}}

        def bad(msg, code=200):
            return jsonify({{"ok": False, "reason": msg, "ts": now(), "path": FILE}}), code

        if request.method == "POST":
            # accept: item | {{item}} | {{items:[...]}}
            if isinstance(body, dict) and isinstance(body.get("items"), list):
                new=[]
                for x in body.get("items") or []:
                    it = norm_item(x)
                    if it: new.append(it)
                if not new: return bad("no valid items")
                byid={{i.get("id"): i for i in items if isinstance(i, dict) and i.get("id")}}
                for it in new: byid[it["id"]] = it
                merged=list(byid.values())
                merged.sort(key=lambda z: (z.get("id") or ""))
                write_atomic(merged)
                return jsonify({{"ok": True, "items": merged, "total": len(merged), "path": FILE, "ts": now()}})

            cand = body.get("item") if isinstance(body, dict) and "item" in body else body
            it = norm_item(cand)
            if not it: return bad("invalid json body")
            out=[]
            seen=False
            for x in items:
                if isinstance(x, dict) and x.get("id")==it["id"]:
                    out.append(it); seen=True
                else:
                    out.append(x)
            if not seen: out.append(it)
            out=[x for x in out if isinstance(x, dict)]
            out.sort(key=lambda z: (z.get("id") or ""))
            write_atomic(out)
            return jsonify({{"ok": True, "created": it, "total": len(out), "path": FILE, "ts": now()}})

        if request.method == "PUT":
            it = norm_item(body if isinstance(body, dict) else None)
            if not it or not it.get("id"): return bad("missing id")
            out=[]
            found=False
            for x in items:
                if isinstance(x, dict) and x.get("id")==it["id"]:
                    out.append(it); found=True
                else:
                    out.append(x)
            if not found: return bad("id not found")
            out=[x for x in out if isinstance(x, dict)]
            out.sort(key=lambda z: (z.get("id") or ""))
            write_atomic(out)
            return jsonify({{"ok": True, "updated": it, "total": len(out), "path": FILE, "ts": now()}})

        if request.method == "DELETE":
            did = (request.args.get("id") or (body.get("id") if isinstance(body, dict) else "") or "").strip()
            if not did: return bad("missing id")
            out=[x for x in items if not (isinstance(x, dict) and x.get("id")==did)]
            if len(out)==len(items): return bad("id not found")
            out.sort(key=lambda z: (z.get("id") or ""))
            write_atomic(out)
            return jsonify({{"ok": True, "deleted": did, "total": len(out), "path": FILE, "ts": now()}})

        return bad("method not supported", 405)

    except Exception as e:
        try:
            from flask import jsonify
            return jsonify({{"ok": False, "reason": "exception", "error": str(e), "ts": 0}}), 200
        except Exception:
            return ("{{\\"ok\\":false}}", 200, {{"Content-Type":"application/json"}})
"""

s = s[:m.start()] + new_func + "\n" + s[m.end():]

# Idempotency marker (optional): add a short comment once
if MARK not in s:
    s = s + f"\\n# {MARK} (installed)\\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched route func:", fname)
print("[OK] marker:", MARK)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [restart] =="
sudo systemctl restart "$SVC" || true
sudo systemctl show "$SVC" -p ActiveState -p SubState -p MainPID -p ExecMainStatus -p ExecMainCode --no-pager || true

echo "== [warm selfcheck] =="
ok=0
for i in $(seq 1 40); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/tmp/_p35_sc.json 2>/tmp/_p35_err; then
    echo "[OK] selfcheck ok (try#$i)"; ok=1; break
  else
    echo "[WARN] not ready (try#$i): $(tr -d '\n' </tmp/_p35_err | head -c 120)"
    sleep 0.2
  fi
done
[ "$ok" -eq 1 ] || { echo "[ERR] UI not reachable"; exit 2; }

echo "== [P35 TEST] =="
RID="ro_test_$(date +%s)"

echo "-- GET0 --"
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"total=",j.get("total"),"path=",j.get("path"))
PY

echo "-- POST --"
cat > /tmp/_ro_post.json <<JSON
{"id":"$RID","tool":"semgrep","rule_id":"TEST.P35.DEMO","action":"suppress","severity_override":"INFO","reason":"p35 smoke","enabled":true}
JSON
curl -fsS -X POST -H 'Content-Type: application/json' --data-binary @/tmp/_ro_post.json \
  "$BASE/api/vsp/rule_overrides_v1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"created_id=",(j.get("created") or {}).get("id"),"total=",j.get("total"))
PY

echo "-- GET1 --"
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
ids=set((x or {}).get("id") for x in (j.get("items") or []) if isinstance(x,dict))
print("has_created=",("'"$RID"'" in ids),"total=",j.get("total"))
PY

echo "-- DELETE --"
curl -fsS -X DELETE "$BASE/api/vsp/rule_overrides_v1?id=$RID" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"deleted=",j.get("deleted"),"total=",j.get("total"))
PY

echo "-- GET2 --"
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
ids=set((x or {}).get("id") for x in (j.get("items") or []) if isinstance(x,dict))
print("removed_ok=",("'"$RID"'" not in ids),"total=",j.get("total"))
PY

echo "== [FILE] =="
ls -lh /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1/rule_overrides.json || true
