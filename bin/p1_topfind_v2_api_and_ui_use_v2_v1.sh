#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
BUNDLE="static/js/vsp_bundle_tabs5_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP"   "${APP}.bak_topfindv2_${TS}"
cp -f "$BUNDLE" "${BUNDLE}.bak_topfindv2_${TS}"
echo "[BACKUP] ${APP}.bak_topfindv2_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_topfindv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

APP=Path("vsp_demo_app.py")
s=APP.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_API_TOP_FINDINGS_V2_RUNFILEALLOW_V1"
if MARK in s:
    print("[OK] API v2 already exists:", MARK)
else:
    block = r'''
# ===== VSP_P1_API_TOP_FINDINGS_V2_RUNFILEALLOW_V1 =====
try:
    from flask import request, jsonify
    import json, urllib.parse, urllib.request

    def _vsp_http_json(url: str, timeout: float = 3.5):
        req = urllib.request.Request(url, headers={"Accept":"application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
        try:
            return json.loads(raw.decode("utf-8","replace"))
        except Exception:
            return None

    @app.get("/api/vsp/top_findings_v2")
    def vsp_top_findings_v2():
        # Honor rid explicitly; fallback to rid_latest only when rid missing.
        rid_req = (request.args.get("rid") or "").strip()
        limit_s = (request.args.get("limit") or "20").strip()
        try:
            limit = int(limit_s)
        except Exception:
            limit = 20
        if limit < 1: limit = 1
        if limit > 200: limit = 200

        # ignore placeholder values
        if rid_req in ("YOUR_RID","...","null","none","_"):
            rid_req = ""

        host = request.host_url.rstrip("/")

        rid_used = rid_req
        if not rid_used:
            j = _vsp_http_json(host + "/api/vsp/rid_latest", timeout=2.5) or {}
            rid_used = (j.get("rid") or "").strip()

        if not rid_used:
            return jsonify({
                "ok": False,
                "err": "no rid (requested missing and rid_latest empty)",
                "rid_requested": rid_req or None,
                "rid_used": None,
                "rid": None,
                "total": 0,
                "limit_applied": limit,
                "items": []
            })

        # Pull findings through the already-correct allowlist API (per rid).
        # Use a bigger limit upstream then slice locally.
        upstream_limit = max(limit, 50)
        q = urllib.parse.urlencode({"rid": rid_used, "path": "findings_unified.json", "limit": str(upstream_limit)})
        url = host + "/api/vsp/run_file_allow?" + q
        data = _vsp_http_json(url, timeout=5.5) or {}

        findings = data.get("findings") or data.get("items") or []
        items = (findings or [])[:limit]

        return jsonify({
            "ok": True,
            "rid_requested": rid_req or rid_used,
            "rid_used": rid_used,
            "rid": rid_used,  # keep for compatibility; UI should trust rid_used
            "from": data.get("from"),
            "total": len(findings or []),
            "limit_applied": limit,
            "items_truncated": True if (findings and len(findings) > limit) else False,
            "items": items,
            "has": data.get("has") or []
        })
except Exception:
    pass
# ===== /VSP_P1_API_TOP_FINDINGS_V2_RUNFILEALLOW_V1 =====
'''
    APP.write_text(s + "\n" + block + "\n", encoding="utf-8")
    print("[OK] appended:", MARK)

py_compile.compile(str(APP), doraise=True)
print("[OK] py_compile PASS")
PY

python3 - <<'PY'
from pathlib import Path
import re

B=Path("static/js/vsp_bundle_tabs5_v1.js")
s=B.read_text(encoding="utf-8", errors="replace")

# Replace v1 -> v2 for dashboard/minicharts sources (safe broad replace)
s2 = s.replace("/api/vsp/top_findings_v1", "/api/vsp/top_findings_v2")

if s2 == s:
    print("[WARN] no occurrences of /api/vsp/top_findings_v1 found in bundle (already replaced?)")
else:
    B.write_text(s2, encoding="utf-8")
    print("[OK] bundle replaced top_findings_v1 -> top_findings_v2")

PY

node --check "$BUNDLE" >/dev/null
echo "[OK] node --check PASS: $BUNDLE"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted: $SVC"
else
  echo "[WARN] systemctl not found; restart service manually"
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_TEST="${1:-VSP_CI_20251218_114312}"

echo
echo "== [TEST] v2 must honor rid =="
curl -fsS "$BASE/api/vsp/top_findings_v2?limit=3&rid=${RID_TEST}" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid_requested=",j.get("rid_requested"),"rid_used=",j.get("rid_used"),"rid=",j.get("rid"),"items_len=",len(j.get("items") or []),"from=",j.get("from"))'

echo
echo "[DONE] Ctrl+Shift+R then open:"
echo "  $BASE/vsp5?rid=${RID_TEST}"
