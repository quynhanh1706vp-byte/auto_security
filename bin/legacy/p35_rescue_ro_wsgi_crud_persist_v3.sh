#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need awk
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl not found"; exit 2; }

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

MARK="VSP_P35_RULE_OVERRIDES_WSGI_CRUD_PERSIST_V3"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_${MARK}_${TS}"
echo "[BACKUP] ${W}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P35_RULE_OVERRIDES_WSGI_CRUD_PERSIST_V3"
if MARK in s:
    print("[OK] marker already present:", MARK)
    raise SystemExit(0)

block = f"""
# --- {MARK} ---
# Commercial: Rule Overrides CRUD+persist at WSGI layer.
# Storage: /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1/rule_overrides.json
__vsp_p35_ro_wrapped_v3 = globals().get("__vsp_p35_ro_wrapped_v3", False)

def __vsp_p35_ro_json(status_code, obj, start_response):
    import json
    body = (json.dumps(obj, ensure_ascii=False, indent=2) + "\\n").encode("utf-8", "replace")
    status = f"{{status_code}} {{'OK' if status_code==200 else 'ERROR'}}"
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store"),
    ]
    start_response(status, headers)
    return [body]

def __vsp_p35_ro_read_body(environ):
    try: n=int(environ.get("CONTENT_LENGTH") or "0")
    except Exception: n=0
    if n<=0: return b""
    try: return environ["wsgi.input"].read(n) or b""
    except Exception: return b""

def __vsp_p35_ro_parse_json(raw):
    import json
    if not raw: return {{}}
    try: return json.loads(raw.decode("utf-8","replace")) or {{}}
    except Exception: return {{}}

def __vsp_p35_ro_load(FILE):
    import json, os
    try:
        if os.path.isfile(FILE):
            with open(FILE,"r",encoding="utf-8") as f: j=json.load(f)
            if isinstance(j,dict) and isinstance(j.get("items"),list):
                return [x for x in j.get("items") if isinstance(x,dict)]
    except Exception:
        pass
    return []

def __vsp_p35_ro_write_atomic(FILE, items):
    import json, os, time
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    tmp=FILE+".tmp"
    data={{"ok":True,"schema":"vsp_rule_overrides_v1","updated_at":int(time.time()),"items":items}}
    with open(tmp,"w",encoding="utf-8") as f:
        json.dump(data,f,ensure_ascii=False,indent=2,sort_keys=False); f.write("\\n")
    os.replace(tmp, FILE)

def __vsp_p35_ro_norm_item(x):
    import time, uuid
    if not isinstance(x,dict): return None
    it=dict(x)
    rid=(it.get("id") or "").strip() or ("ro_"+uuid.uuid4().hex[:12])
    it["id"]=rid
    it.setdefault("enabled", True)
    it.setdefault("action", it.get("op") or "suppress")
    it.setdefault("reason", it.get("note") or "")
    it["updated_at"]=int(time.time())
    return it

def __vsp_p35_ro_handle(environ, start_response):
    import os, time, urllib.parse
    ROOT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1"
    FILE=os.path.join(ROOT,"rule_overrides.json")
    method=(environ.get("REQUEST_METHOD") or "GET").upper()
    qs=urllib.parse.parse_qs(environ.get("QUERY_STRING") or "")
    items=__vsp_p35_ro_load(FILE)

    def ok(obj):
        obj.setdefault("ok", True); obj.setdefault("ts", int(time.time()))
        obj.setdefault("path", FILE)
        return __vsp_p35_ro_json(200, obj, start_response)

    def bad(reason):
        return __vsp_p35_ro_json(200, {{"ok":False,"reason":reason,"ts":int(time.time()),"path":FILE}}, start_response)

    if method=="GET":
        return ok({{"items":items,"total":len(items)}})

    raw=__vsp_p35_ro_read_body(environ)
    body=__vsp_p35_ro_parse_json(raw)

    if method=="POST":
        if isinstance(body,dict) and isinstance(body.get("items"),list):
            new=[]
            for x in body.get("items") or []:
                it=__vsp_p35_ro_norm_item(x)
                if it: new.append(it)
            if not new: return bad("no valid items")
            byid={{i.get("id"):i for i in items if isinstance(i,dict) and i.get("id")}}
            for it in new: byid[it["id"]] = it
            merged=list(byid.values()); merged.sort(key=lambda z:(z.get("id") or ""))
            __vsp_p35_ro_write_atomic(FILE, merged)
            return ok({{"items":merged,"total":len(merged)}})

        cand = body.get("item") if isinstance(body,dict) and "item" in body else body
        it=__vsp_p35_ro_norm_item(cand)
        if not it: return bad("invalid json body")
        out=[]; seen=False
        for x in items:
            if isinstance(x,dict) and x.get("id")==it["id"]:
                out.append(it); seen=True
            else:
                out.append(x)
        if not seen: out.append(it)
        out=[x for x in out if isinstance(x,dict)]
        out.sort(key=lambda z:(z.get("id") or ""))
        __vsp_p35_ro_write_atomic(FILE, out)
        return ok({{"created":it,"total":len(out)}})

    if method=="PUT":
        it=__vsp_p35_ro_norm_item(body if isinstance(body,dict) else None)
        if not it or not it.get("id"): return bad("missing id")
        out=[]; found=False
        for x in items:
            if isinstance(x,dict) and x.get("id")==it["id"]:
                out.append(it); found=True
            else:
                out.append(x)
        if not found: return bad("id not found")
        out=[x for x in out if isinstance(x,dict)]
        out.sort(key=lambda z:(z.get("id") or ""))
        __vsp_p35_ro_write_atomic(FILE, out)
        return ok({{"updated":it,"total":len(out)}})

    if method=="DELETE":
        did=""
        try: did=(qs.get("id",[""])[0] or "").strip()
        except Exception: did=""
        if not did and isinstance(body,dict): did=(body.get("id") or "").strip()
        if not did: return bad("missing id")
        out=[x for x in items if not (isinstance(x,dict) and x.get("id")==did)]
        if len(out)==len(items): return bad("id not found")
        out.sort(key=lambda z:(z.get("id") or ""))
        __vsp_p35_ro_write_atomic(FILE, out)
        return ok({{"deleted":did,"total":len(out)}})

    return bad("method not supported")

try:
    if not __vsp_p35_ro_wrapped_v3:
        _orig_app = globals().get("application", None)
        if callable(_orig_app):
            def application(environ, start_response):
                try:
                    path=(environ.get("PATH_INFO") or "")
                    if path in ("/api/vsp/rule_overrides_v1","/api/vsp/rule_overrides_ui_v1"):
                        return __vsp_p35_ro_handle(environ, start_response)
                except Exception:
                    pass
                return _orig_app(environ, start_response)
            globals()["__vsp_p35_ro_wrapped_v3"] = True
except Exception:
    pass
# --- /{MARK} ---
"""
p.write_text(s.rstrip()+"\n"+block+"\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [restart] =="
sudo systemctl restart "$SVC" || true
sudo systemctl show "$SVC" -p ActiveState -p SubState -p MainPID -p ExecMainStatus -p ExecMainCode --no-pager || true

echo "== [warm selfcheck] =="
ok=0
for i in $(seq 1 30); do
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
