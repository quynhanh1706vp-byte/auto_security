#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P0_FINDINGS_PAGE_API_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_findingspage_${TS}"
echo "[BACKUP] ${W}.bak_findingspage_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P0_FINDINGS_PAGE_API_V1" in s:
    print("[SKIP] marker already present")
else:
    block = textwrap.dedent(r'''
    # ===================== VSP_P0_FINDINGS_PAGE_API_V1 =====================
    # GET /api/vsp/findings_page?rid=...&offset=0&limit=200&severity=&tool=&q=
    try:
        import json, time
        from pathlib import Path as _Path

        _VSP_FINDINGS_PAGE_CACHE = {"ts": 0.0, "rid": None, "items": None}

        def _vsp_fp_find_run_dir(rid: str):
            # bounded search; keep consistent with manifest v3 approach
            roots = [
                _Path("/home/test/Data/SECURITY-10-10-v4/out_ci"),
                _Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
            ]
            for root in roots:
                if not root.is_dir():
                    continue
                cand = root / rid
                if cand.is_dir():
                    return str(cand)
            # fallback: scan recent dirs
            for root in roots:
                if not root.is_dir():
                    continue
                try:
                    ds = [d for d in root.iterdir() if d.is_dir()]
                    ds.sort(key=lambda x: x.stat().st_mtime, reverse=True)
                    for d in ds[:220]:
                        if d.name == rid:
                            return str(d)
                except Exception:
                    pass
            return None

        def _vsp_fp_load_findings(rid: str):
            now = time.time()
            if _VSP_FINDINGS_PAGE_CACHE.get("rid")==rid and (now - float(_VSP_FINDINGS_PAGE_CACHE.get("ts") or 0)) < 8.0:
                return _VSP_FINDINGS_PAGE_CACHE.get("items") or []

            rd = _vsp_fp_find_run_dir(rid)
            if not rd:
                return None
            fu = _Path(rd) / "findings_unified.json"
            if not fu.is_file():
                return []

            try:
                j = json.loads(fu.read_text(encoding="utf-8", errors="replace"))
            except Exception:
                return []

            items = []
            if isinstance(j, dict) and isinstance(j.get("findings"), list):
                items = j["findings"]
            elif isinstance(j, list):
                items = j
            else:
                items = []

            _VSP_FINDINGS_PAGE_CACHE["ts"]=now
            _VSP_FINDINGS_PAGE_CACHE["rid"]=rid
            _VSP_FINDINGS_PAGE_CACHE["items"]=items
            return items

        @app.get("/api/vsp/findings_page")
        def vsp_findings_page():
            rid = (request.args.get("rid") or "").strip()
            if not rid:
                return jsonify({"ok": False, "err": "missing rid"}), 400

            try:
                offset = int(request.args.get("offset") or "0")
                limit  = int(request.args.get("limit") or "200")
            except Exception:
                offset, limit = 0, 200
            offset = max(0, offset)
            limit = min(max(1, limit), 500)

            severity = (request.args.get("severity") or "").strip().upper()
            tool = (request.args.get("tool") or "").strip()
            q = (request.args.get("q") or "").strip().lower()

            items = _vsp_fp_load_findings(rid)
            if items is None:
                return jsonify({"ok": False, "err": "rid not found", "rid": rid}), 200

            def ok_item(x):
                if not isinstance(x, dict):
                    return False
                if severity:
                    s = (x.get("severity") or x.get("sev") or "").upper()
                    if s != severity:
                        return False
                if tool:
                    t = (x.get("tool") or x.get("scanner") or x.get("source") or "")
                    if t != tool:
                        return False
                if q:
                    blob = (" ".join([
                        str(x.get("rule_id") or ""),
                        str(x.get("id") or ""),
                        str(x.get("title") or ""),
                        str(x.get("message") or ""),
                        str(x.get("file") or x.get("path") or ""),
                    ])).lower()
                    if q not in blob:
                        return False
                return True

            filtered = [x for x in items if ok_item(x)]
            total = len(filtered)
            page = filtered[offset: offset + limit]

            # return a trimmed projection for UI
            out=[]
            for x in page:
                out.append({
                    "severity": x.get("severity") or x.get("sev"),
                    "tool": x.get("tool") or x.get("scanner") or x.get("source"),
                    "rule_id": x.get("rule_id") or x.get("id"),
                    "title": x.get("title") or x.get("check_name") or x.get("message"),
                    "file": x.get("file") or x.get("path"),
                    "line": x.get("line") or x.get("start_line") or x.get("location",{}).get("line"),
                })

            return jsonify({
                "ok": True,
                "rid": rid,
                "offset": offset,
                "limit": limit,
                "total": total,
                "page": out
            }), 200

    except Exception:
        pass
    # ===================== /VSP_P0_FINDINGS_PAGE_API_V1 =====================
    ''').strip("\n")

    # append near EOF
    s = s + "\n\n" + block + "\n"
    p.write_text(s, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("[OK] appended findings_page api")

# validate compile
py_compile.compile(str(p), doraise=True)
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: findings_page (limit=3) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
curl -fsS "$BASE/api/vsp/findings_page?rid=$RID&offset=0&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"total=",j.get("total"),"page_len=",len(j.get("page") or []))'
echo "[DONE]"
