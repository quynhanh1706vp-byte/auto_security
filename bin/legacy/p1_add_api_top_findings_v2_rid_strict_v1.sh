#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sudo

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_v2_ridstrict_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_v2_ridstrict_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_API_TOP_FINDINGS_V2_RID_STRICT_V1"
if marker in s:
    print("[OK] already patched:", marker)
else:
    # append a new endpoint at EOF to avoid fighting existing routes/hooks
    block = r'''
# ===== VSP_P1_API_TOP_FINDINGS_V2_RID_STRICT_V1 =====
try:
    from flask import request, jsonify
except Exception:
    request = None
    jsonify = None

def _vsp__sev_rank(x):
    m = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3,"INFO":4,"TRACE":5}
    return m.get((x or "").upper(), 9)

def _vsp__http_get_json(url, timeout=3.5):
    import json, urllib.request
    req = urllib.request.Request(url, headers={"Accept":"application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8","replace"))

def _vsp__host_base():
    # prefer request.host_url if present; fallback to localhost
    try:
        if request and getattr(request, "host_url", None):
            return request.host_url.rstrip("/")
    except Exception:
        pass
    return "http://127.0.0.1:8910"

def _vsp__rid_latest():
    base = _vsp__host_base()
    try:
        j = _vsp__http_get_json(base + "/api/vsp/rid_latest", timeout=2.5)
        rid = (j.get("rid") or "").strip()
        return rid
    except Exception:
        return ""

def _vsp__load_findings_via_allow(rid, limit_load=800):
    base = _vsp__host_base()
    # Use existing allowlist endpoint to avoid internal path / GLOBAL_BEST logic.
    url = f"{base}/api/vsp/run_file_allow?rid={rid}&path=findings_unified.json&limit={int(limit_load)}"
    j = _vsp__http_get_json(url, timeout=6.0)
    arr = j.get("findings") or []
    return arr, j.get("from"), j.get("err") or ""

# define endpoint only if Flask app exists
try:
    app
    @app.get("/api/vsp/top_findings_v2")
    def vsp_api_top_findings_v2():
        rid_req = (request.args.get("rid","") if request else "").strip()
        limit = int((request.args.get("limit","10") if request else "10") or 10)
        limit = max(1, min(limit, 200))

        rid_used = rid_req if (rid_req and rid_req not in ("YOUR_RID","latest","auto")) else _vsp__rid_latest()
        if not rid_used:
            return jsonify({"ok": False, "rid_requested": rid_req, "rid_used": rid_used, "rid": rid_used,
                            "items": [], "total": 0, "err": "no rid available"}), 200

        findings, src_from, err = _vsp__load_findings_via_allow(rid_used, limit_load=900)
        if not findings:
            return jsonify({"ok": True, "rid_requested": rid_req, "rid_used": rid_used, "rid": rid_used,
                            "items": [], "total": 0, "from": src_from, "err": err, "rid_source":"requested" if rid_req else "rid_latest"}), 200

        # sort by severity rank then tool/title
        try:
            findings_sorted = sorted(findings, key=lambda f: (_vsp__sev_rank((f or {}).get("severity")), (f or {}).get("tool",""), (f or {}).get("title","")))
        except Exception:
            findings_sorted = findings

        items = findings_sorted[:limit]
        return jsonify({
            "ok": True,
            "rid_requested": rid_req,
            "rid_used": rid_used,
            "rid": rid_used,
            "rid_source": "requested" if rid_req else "rid_latest",
            "total": len(findings),
            "limit_applied": limit,
            "items": items,
            "from": src_from,
            "err": err
        }), 200
except Exception:
    pass
# ===== end VSP_P1_API_TOP_FINDINGS_V2_RID_STRICT_V1 =====
'''
    s = s.rstrip() + "\n\n" + textwrap.dedent(block).lstrip("\n") + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", marker)

py_compile.compile("vsp_demo_app.py", doraise=True)
print("[OK] py_compile PASS")
PY

sudo systemctl restart "$SVC"
echo "[OK] restarted: $SVC"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== [TEST] v2 must honor rid =="
RID_TEST="${1:-VSP_CI_20251218_114312}"
curl -fsS "$BASE/api/vsp/top_findings_v2?limit=3&rid=$RID_TEST" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid_requested=",j.get("rid_requested"),"rid_used=",j.get("rid_used"),"rid=",j.get("rid"),"items_len=",len(j.get("items") or []),"from=",j.get("from"))'
