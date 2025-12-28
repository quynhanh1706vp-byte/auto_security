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

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_fixwrap_v5_${TS}"
echo "[BACKUP] ${W}.bak_fixwrap_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

def rm_block(marker: str):
    global s
    pat = re.compile(r"(?s)\n# --- "+re.escape(marker)+r" ---.*?\n# --- /"+re.escape(marker)+r" ---\n")
    s2,n = pat.subn("\n", s)
    if n:
        print("[OK] removed", marker, "x", n)
    s = s2

# 1) Remove known-bad / old wrappers (avoid recursion chains)
for m in [
    "VSP_P34_CSP_RO_WSGI_WRAP_V3",
    "VSP_P35_RULE_OVERRIDES_WSGI_CRUD_PERSIST_V2",
    "VSP_P35_RULE_OVERRIDES_WSGI_CRUD_PERSIST_V3",
]:
    rm_block(m)

# Also remove any older P34 WSGI wrap variants if present (best-effort)
for mm in re.findall(r"VSP_P34_CSP_RO_WSGI_WRAP_V\d+", s):
    rm_block(mm)

# 2) Install single safe wrapper V5 (idempotent)
MARK="VSP_P34P35_SINGLE_WSGI_WRAP_V5"
if MARK in s:
    print("[OK] already present:", MARK)
else:
    csp = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'"
    block = f"""
# --- {MARK} ---
# Commercial: SINGLE safe WSGI wrapper (no recursion):
# - inject CSP-Report-Only for text/html (covers cached HIT-RAM/HIT-DISK responses)
# - implement Rule Overrides CRUD+persist for /api/vsp/rule_overrides_v1 (+ _ui_v1)
__vsp_wrap_v5_installed = globals().get("__vsp_wrap_v5_installed", False)

def __vsp_v5_wrap_start_response(start_response):
    def _sr(status, headers, exc_info=None):
        try:
            ct = ""
            has = False
            for k,v in headers:
                lk = (k or "").lower()
                if lk == "content-type":
                    ct = (v or "").lower()
                elif lk == "content-security-policy-report-only":
                    has = True
            if ("text/html" in ct) and (not has):
                headers.append(("Content-Security-Policy-Report-Only", "{csp}"))
        except Exception:
            pass
        return start_response(status, headers, exc_info)
    return _sr

def __vsp_v5_json(start_response, obj, code=200):
    import json
    body = (json.dumps(obj, ensure_ascii=False, indent=2) + "\\n").encode("utf-8", "replace")
    start_response(f"{{code}} OK", [
        ("Content-Type","application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control","no-store"),
    ])
    return [body]

def __vsp_v5_read_body(environ):
    try: n=int(environ.get("CONTENT_LENGTH") or "0")
    except Exception: n=0
    if n<=0: return b""
    try: return environ["wsgi.input"].read(n) or b""
    except Exception: return b""

def __vsp_v5_parse_json(raw):
    import json
    if not raw: return {{}}
    try: return json.loads(raw.decode("utf-8","replace")) or {{}}
    except Exception: return {{}}

def __vsp_v5_ro_handle(environ, start_response):
    import os, time, json, uuid, urllib.parse
    ROOT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1"
    FILE=os.path.join(ROOT,"rule_overrides.json")
    os.makedirs(ROOT, exist_ok=True)

    def now(): return int(time.time())

    def load_items():
        try:
            if os.path.isfile(FILE):
                j=json.load(open(FILE,"r",encoding="utf-8"))
                if isinstance(j,dict) and isinstance(j.get("items"),list):
                    return [x for x in j["items"] if isinstance(x,dict)]
        except Exception:
            pass
        return []

    def write_atomic(items):
        tmp=FILE+".tmp"
        data={{"ok":True,"schema":"vsp_rule_overrides_v1","updated_at":now(),"items":items}}
        with open(tmp,"w",encoding="utf-8") as f:
            json.dump(data,f,ensure_ascii=False,indent=2,sort_keys=False); f.write("\\n")
        os.replace(tmp, FILE)

    def norm_item(x):
        if not isinstance(x,dict): return None
        it=dict(x)
        rid=(it.get("id") or "").strip() or ("ro_"+uuid.uuid4().hex[:12])
        it["id"]=rid
        it.setdefault("enabled", True)
        it.setdefault("action", it.get("op") or "suppress")
        it.setdefault("reason", it.get("note") or "")
        it["updated_at"]=now()
        return it

    method=(environ.get("REQUEST_METHOD") or "GET").upper()
    qs=urllib.parse.parse_qs(environ.get("QUERY_STRING") or "")
    items=load_items()

    if method=="GET":
        return __vsp_v5_json(start_response, {{"ok":True,"items":items,"total":len(items),"path":FILE,"ts":now()}})

    body=__vsp_v5_parse_json(__vsp_v5_read_body(environ))

    def bad(msg):
        return __vsp_v5_json(start_response, {{"ok":False,"reason":msg,"path":FILE,"ts":now()}})

    if method=="POST":
        if isinstance(body,dict) and isinstance(body.get("items"),list):
            new=[]
            for x in body.get("items") or []:
                it=norm_item(x)
                if it: new.append(it)
            if not new: return bad("no valid items")
            byid={{i.get("id"):i for i in items if isinstance(i,dict) and i.get("id")}}
            for it in new: byid[it["id"]] = it
            merged=list(byid.values()); merged.sort(key=lambda z:(z.get("id") or ""))
            write_atomic(merged)
            return __vsp_v5_json(start_response, {{"ok":True,"items":merged,"total":len(merged),"path":FILE,"ts":now()}})
        cand = body.get("item") if isinstance(body,dict) and "item" in body else body
        it=norm_item(cand)
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
        write_atomic(out)
        return __vsp_v5_json(start_response, {{"ok":True,"created":it,"total":len(out),"path":FILE,"ts":now()}})

    if method=="PUT":
        it=norm_item(body if isinstance(body,dict) else None)
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
        write_atomic(out)
        return __vsp_v5_json(start_response, {{"ok":True,"updated":it,"total":len(out),"path":FILE,"ts":now()}})

    if method=="DELETE":
        did=""
        try: did=(qs.get("id",[""])[0] or "").strip()
        except Exception: did=""
        if not did and isinstance(body,dict): did=(body.get("id") or "").strip()
        if not did: return bad("missing id")
        out=[x for x in items if not (isinstance(x,dict) and x.get("id")==did)]
        if len(out)==len(items): return bad("id not found")
        out.sort(key=lambda z:(z.get("id") or ""))
        write_atomic(out)
        return __vsp_v5_json(start_response, {{"ok":True,"deleted":did,"total":len(out),"path":FILE,"ts":now()}})

    return bad("method not supported")

try:
    if not __vsp_wrap_v5_installed:
        __vsp_orig_app_v5 = globals().get("__vsp_orig_app_v5")
        if __vsp_orig_app_v5 is None:
            __vsp_orig_app_v5 = globals().get("application")
            globals()["__vsp_orig_app_v5"] = __vsp_orig_app_v5

        # Guard: never wrap if orig is missing or already our wrapper
        if callable(__vsp_orig_app_v5):
            def application(environ, start_response):
                try:
                    path=(environ.get("PATH_INFO") or "")
                    if path in ("/api/vsp/rule_overrides_v1","/api/vsp/rule_overrides_ui_v1"):
                        return __vsp_v5_ro_handle(environ, start_response)
                except Exception:
                    pass
                return __vsp_orig_app_v5(environ, __vsp_v5_wrap_start_response(start_response))

            application.__vsp_wrap_v5__ = True
            globals()["__vsp_wrap_v5_installed"] = True
except Exception:
    pass
# --- /{MARK} ---
"""
    s = s.rstrip() + "\n" + block + "\n"
    print("[OK] appended:", MARK)

p.write_text(s, encoding="utf-8")
print("[OK] write done")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [restart] =="
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" || true

echo "== [warm selfcheck] =="
ok=0
for i in $(seq 1 40); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/selfcheck_p0" >/tmp/_sc.json 2>/tmp/_err; then
    echo "[OK] selfcheck ok (try#$i)"; ok=1; break
  else
    echo "[WARN] not ready (try#$i): $(tr -d '\n' </tmp/_err | head -c 120)"
    sleep 0.2
  fi
done
[ "$ok" -eq 1 ] || { echo "[ERR] UI still failing"; exit 2; }

echo "== [CHECK] CSP_RO on GET /vsp5 =="
curl -fsS -D- -o /dev/null "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Security-Policy-Report-Only:/{print}'

echo "== [P35 TEST] rule_overrides CRUD =="
RID="ro_test_$(date +%s)"
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("[GET0] ok=",j.get("ok"),"total=",j.get("total"),"path=",j.get("path"))
PY

echo "{\"id\":\"$RID\",\"tool\":\"semgrep\",\"rule_id\":\"TEST.P35.DEMO\",\"action\":\"suppress\",\"severity_override\":\"INFO\",\"reason\":\"p35 smoke\",\"enabled\":true}" \
 | curl -fsS -X POST -H 'Content-Type: application/json' --data-binary @- "$BASE/api/vsp/rule_overrides_v1" \
 | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("[POST] ok=",j.get("ok"),"created_id=",(j.get("created") or {}).get("id"),"total=",j.get("total"))
PY

curl -fsS -X DELETE "$BASE/api/vsp/rule_overrides_v1?id=$RID" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("[DEL] ok=",j.get("ok"),"deleted=",j.get("deleted"),"total=",j.get("total"))
PY

ls -lh /home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v1/rule_overrides.json || true
