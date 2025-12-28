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

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_findingspage_v2_${TS}"
echo "[BACKUP] ${W}.bak_findingspage_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

start = r"# ===================== VSP_P0_FINDINGS_PAGE_API_V1 ====================="
end   = r"# ===================== /VSP_P0_FINDINGS_PAGE_API_V1 ====================="

if start not in s or end not in s:
    raise SystemExit("[ERR] cannot find V1 markers in wsgi_vsp_ui_gateway.py (block missing?)")

block_v2 = textwrap.dedent(r'''
# ===================== VSP_P0_FINDINGS_PAGE_API_V2_FIXRID_V1 =====================
# GET /api/vsp/findings_page?rid=...&offset=0&limit=200&severity=&tool=&q=&debug=1
try:
    import json, time
    from pathlib import Path as _Path

    _VSP_FP_CACHE = {"ts": 0.0, "rid": None, "run_dir": None, "items": None}

    def _vsp_fp_roots():
        # keep aligned with your ecosystem (SECURITY-10-10-v4 + SECURITY_BUNDLE + UI out_ci)
        roots = [
            _Path("/home/test/Data/SECURITY-10-10-v4/out_ci"),
            _Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
            _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        ]
        # allow override via env (optional)
        try:
            import os as _os
            extra = (_os.environ.get("VSP_OUT_CI_ROOTS") or "").strip()
            if extra:
                for x in extra.split(":"):
                    x=x.strip()
                    if x:
                        roots.append(_Path(x))
        except Exception:
            pass
        # de-dup while preserving order
        out=[]
        seen=set()
        for r in roots:
            rs=str(r)
            if rs in seen: 
                continue
            seen.add(rs)
            out.append(r)
        return out

    def _vsp_fp_find_run_dir(rid: str):
        roots = _vsp_fp_roots()
        # fast path root/rid
        for root in roots:
            try:
                if root.is_dir():
                    cand = root / rid
                    if cand.is_dir():
                        return str(cand)
            except Exception:
                pass
        # bounded scan newest dirs
        for root in roots:
            try:
                if not root.is_dir():
                    continue
                ds = [d for d in root.iterdir() if d.is_dir()]
                ds.sort(key=lambda x: x.stat().st_mtime, reverse=True)
                for d in ds[:260]:
                    if d.name == rid:
                        return str(d)
            except Exception:
                pass
        return None

    def _vsp_fp_load_findings(rid: str):
        now = time.time()
        if _VSP_FP_CACHE.get("rid")==rid and (now - float(_VSP_FP_CACHE.get("ts") or 0)) < 8.0:
            return _VSP_FP_CACHE.get("run_dir"), (_VSP_FP_CACHE.get("items") or [])

        rd = _vsp_fp_find_run_dir(rid)
        if not rd:
            return None, None

        fu = _Path(rd) / "findings_unified.json"
        if not fu.is_file():
            _VSP_FP_CACHE.update({"ts": now, "rid": rid, "run_dir": rd, "items": []})
            return rd, []

        try:
            j = json.loads(fu.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            _VSP_FP_CACHE.update({"ts": now, "rid": rid, "run_dir": rd, "items": []})
            return rd, []

        items = []
        if isinstance(j, dict) and isinstance(j.get("findings"), list):
            items = j["findings"]
        elif isinstance(j, list):
            items = j
        else:
            items = []

        _VSP_FP_CACHE.update({"ts": now, "rid": rid, "run_dir": rd, "items": items})
        return rd, items

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
        debug = (request.args.get("debug") or "").strip() in ("1","true","yes","on")

        run_dir, items = _vsp_fp_load_findings(rid)
        if items is None:
            out = {"ok": False, "err": "rid not found", "rid": rid}
            if debug:
                out.update({
                    "run_dir": run_dir,
                    "roots": [str(x) for x in _vsp_fp_roots()],
                })
            return jsonify(out), 200

        # filter
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

        filtered = [x for x in (items or []) if ok_item(x)]
        total = len(filtered)
        page = filtered[offset: offset + limit]

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

        resp = {"ok": True, "rid": rid, "offset": offset, "limit": limit, "total": total, "page": out}
        if debug:
            resp["run_dir"] = run_dir
            fu = _Path(run_dir)/"findings_unified.json"
            resp["findings_path"] = str(fu)
            resp["findings_exists"] = fu.is_file()
            try:
                resp["findings_bytes"] = fu.stat().st_size if fu.is_file() else 0
            except Exception:
                resp["findings_bytes"] = None
        return jsonify(resp), 200

except Exception:
    pass
# ===================== /VSP_P0_FINDINGS_PAGE_API_V2_FIXRID_V1 =====================
''').strip("\n")

# replace whole V1 block with V2 block (keep V1 markers removed to avoid confusion)
pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
s2 = pattern.sub(block_v2, s, count=1)
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] replaced findings_page block -> V2")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke v2: findings_page debug (limit=3) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
curl -fsS "$BASE/api/vsp/findings_page?rid=$RID&offset=0&limit=3&debug=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"total=",j.get("total"),"page_len=",len(j.get("page") or []),"run_dir=",j.get("run_dir"))'
echo "[DONE]"
