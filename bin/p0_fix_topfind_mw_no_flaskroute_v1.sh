#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_topfind_mw_${TS}"
echo "[BACKUP] ${W}.bak_topfind_mw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Remove any previously injected V5B/V5C blocks that might have @app.route and crash import
for mk in ["VSP_P0_TOPFIND_GATEWAY_V5C", "VSP_P0_TOPFIND_GATEWAY_V5B"]:
    s = re.sub(r'(?s)^\s*#\s*'+re.escape(mk)+r'.*?^\s*#\s*END\s*'+re.escape(mk)+r'\s*$',
               '', s, flags=re.M)

# also strip any decorator lines we injected (extra safety)
s = re.sub(r'^\s*@app\.route\("/api/vsp/top_findings_v1".*\)\s*$\n', '', s, flags=re.M)

def ensure_import(line: str):
    global s
    if re.search(r'^\s*' + re.escape(line) + r'\s*$', s, flags=re.M):
        return
    m = re.search(r'^(?:import .*|from .* import .*)(?:\n(?:import .*|from .* import .*))*\n', s, flags=re.M)
    if m:
        s = s[:m.end()] + line + "\n" + s[m.end():]
    else:
        s = line + "\n" + s

for line in [
    "import os",
    "import json",
    "import glob",
    "import re",
    "import csv",
    "import time",
    "from datetime import datetime",
    "from urllib.parse import parse_qs",
]:
    ensure_import(line)

MARK = "VSP_P0_TOPFIND_MW_NO_FLASKROUTE_V1"

mw_block = r'''
# VSP_P0_TOPFIND_MW_NO_FLASKROUTE_V1
def _vsp__sev_weight(sev: str) -> int:
    m = {"CRITICAL": 600, "HIGH": 500, "MEDIUM": 400, "LOW": 300, "INFO": 200, "TRACE": 100}
    return m.get((sev or "").upper(), 0)

def _vsp__sanitize_path(pth: str) -> str:
    if not pth:
        return ""
    pth = (pth or "").replace("\\", "/")
    pth = re.sub(r"^/+", "", pth)
    parts = [x for x in pth.split("/") if x]
    return "/".join(parts[-4:]) if len(parts) > 4 else "/".join(parts)

def _vsp__candidate_run_roots():
    return [
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]

def _vsp__iter_run_dirs():
    for root in _vsp__candidate_run_roots():
        try:
            if not os.path.isdir(root):
                continue
            for d in glob.glob(os.path.join(root, "VSP_*")):
                if os.path.isdir(d):
                    yield d
        except Exception:
            continue

def _vsp__json_findings(fp: str):
    try:
        obj = json.load(open(fp, "r", encoding="utf-8"))
        if isinstance(obj, dict) and isinstance(obj.get("findings"), list):
            return obj["findings"]
        if isinstance(obj, list):
            return obj
    except Exception:
        return None
    return None

def _vsp__csv_rows(fp: str, max_rows: int = 2000):
    # return list of dict rows; empty if only header
    rows = []
    try:
        with open(fp, "r", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            for i, row in enumerate(r):
                if i >= max_rows:
                    break
                if row:
                    rows.append(row)
    except Exception:
        return None
    return rows

def _vsp__load_findings_from_run_dir(run_dir: str):
    # priority: json -> csv (sarif ignored here to keep it safe/simple)
    jpaths = [
        os.path.join(run_dir, "reports", "findings_unified.json"),
        os.path.join(run_dir, "findings_unified.json"),
        os.path.join(run_dir, "report", "findings_unified.json"),
    ]
    for fp in jpaths:
        if os.path.isfile(fp) and os.path.getsize(fp) > 10:
            arr = _vsp__json_findings(fp)
            if isinstance(arr, list) and len(arr) > 0:
                return arr

    cfp = os.path.join(run_dir, "reports", "findings_unified.csv")
    if os.path.isfile(cfp) and os.path.getsize(cfp) > 10:
        rows = _vsp__csv_rows(cfp)
        if rows is None:
            return None
        if len(rows) == 0:
            return []  # header-only => empty findings
        out = []
        for row in rows:
            out.append({
                "tool": row.get("tool") or row.get("scanner") or row.get("source"),
                "severity": (row.get("severity") or "").upper(),
                "title": row.get("title") or row.get("message") or row.get("name"),
                "cwe": row.get("cwe") or row.get("cwe_id"),
                "rule_id": row.get("rule_id") or row.get("check_id") or row.get("id"),
                "file": row.get("file") or row.get("path") or "",
                "line": row.get("line") or row.get("start_line") or row.get("line_start"),
            })
        return out

    return None

def _vsp__pick_latest_rid_with_nonempty_findings():
    best = ("", -1.0)
    for d in _vsp__iter_run_dirs():
        try:
            rid = os.path.basename(d)
            mt = os.path.getmtime(d)
            findings = _vsp__load_findings_from_run_dir(d)
            if isinstance(findings, list) and len(findings) > 0:
                if mt > best[1]:
                    best = (rid, mt)
        except Exception:
            continue
    return best[0] or ""

def _vsp__find_run_dir_for_rid(rid: str) -> str:
    if not rid:
        return ""
    for root in _vsp__candidate_run_roots():
        d = os.path.join(root, rid)
        if os.path.isdir(d):
            return d
    # prefix match latest
    best = ("", -1.0)
    for root in _vsp__candidate_run_roots():
        try:
            for d in glob.glob(os.path.join(root, rid + "*")):
                if os.path.isdir(d):
                    mt = os.path.getmtime(d)
                    if mt > best[1]:
                        best = (d, mt)
        except Exception:
            continue
    return best[0] or ""

def _vsp__normalize_items(raw):
    items = []
    if not raw:
        return items
    for f in raw:
        if not isinstance(f, dict):
            continue
        items.append({
            "tool": f.get("tool"),
            "severity": (f.get("severity") or "").upper(),
            "title": f.get("title"),
            "cwe": f.get("cwe"),
            "rule_id": f.get("rule_id") or f.get("check_id") or f.get("id"),
            "file": _vsp__sanitize_path(f.get("file") or f.get("path") or ""),
            "line": f.get("line") or f.get("start_line") or f.get("line_start"),
        })
    items.sort(key=lambda x: (_vsp__sev_weight(x.get("severity")), str(x.get("title") or "")), reverse=True)
    return items

class _VspTopFindingsMW:
    def __init__(self, app):
        self.app = app
        self._cache = {"t": 0.0, "key": "", "body": None}

    def __call__(self, environ, start_response):
        try:
            if environ.get("PATH_INFO") != "/api/vsp/top_findings_v1":
                return self.app(environ, start_response)

            qs = parse_qs(environ.get("QUERY_STRING", ""), keep_blank_values=True)
            rid_req = (qs.get("rid", [""])[0] or "").strip()
            try:
                limit = int((qs.get("limit", ["5"])[0] or "5"))
            except Exception:
                limit = 5
            if limit < 1: limit = 1
            if limit > 50: limit = 50

            key = f"{rid_req}:{limit}"
            now = time.time()
            if self._cache["body"] is not None and self._cache["key"] == key and (now - self._cache["t"]) < 3.0:
                body = self._cache["body"]
            else:
                rid_used = rid_req
                run_dir = _vsp__find_run_dir_for_rid(rid_used) if rid_used else ""
                findings = _vsp__load_findings_from_run_dir(run_dir) if run_dir else None

                # fallback: if requested rid has none/empty => pick latest rid with nonempty findings
                if not isinstance(findings, list) or len(findings) == 0:
                    rid2 = _vsp__pick_latest_rid_with_nonempty_findings()
                    if rid2:
                        rid_used = rid2
                        run_dir = _vsp__find_run_dir_for_rid(rid2)
                        findings = _vsp__load_findings_from_run_dir(run_dir) if run_dir else None

                items = _vsp__normalize_items(findings if isinstance(findings, list) else [])
                ok = True
                reason = None
                if findings is None:
                    ok = False
                    reason = "NO_USABLE_SOURCE"
                elif isinstance(findings, list) and len(findings) == 0:
                    # commercial-safe: no findings but endpoint is healthy
                    ok = True
                    reason = "NO_FINDINGS"

                payload = {
                    "ok": ok,
                    "rid": rid_used or "",
                    "rid_requested": rid_req or None,
                    "rid_used": rid_used or None,
                    "total": len(items),
                    "items": items[:limit],
                    "reason": reason,
                    "err": reason or "",  # backward compatible
                    "has": ["json:findings_unified.json", "csv:reports/findings_unified.csv", "sarif:reports/findings_unified.sarif"],
                    "ts": datetime.utcnow().isoformat() + "Z",
                }
                body = (json.dumps(payload, ensure_ascii=False)).encode("utf-8")
                self._cache = {"t": now, "key": key, "body": body}

            headers = [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Cache-Control", "no-store"),
                ("X-Content-Type-Options", "nosniff"),
            ]
            start_response("200 OK", headers)
            return [body]
        except Exception:
            # never crash worker
            start_response("200 OK", [("Content-Type", "application/json; charset=utf-8"), ("Cache-Control", "no-store")])
            return [b'{"ok":false,"total":0,"items":[],"reason":"EXCEPTION"}']

def _vsp__install_topfind_mw(app):
    try:
        return _VspTopFindingsMW(app)
    except Exception:
        return app
# END VSP_P0_TOPFIND_MW_NO_FLASKROUTE_V1
'''

if MARK not in s:
    s = s.rstrip() + "\n\n" + mw_block.strip() + "\n"

# 2) Wrap the final WSGI callable "application" if it exists
# We DO NOT touch "app" (it may be middleware), only wrap "application".
if re.search(r'^\s*application\s*=\s*', s, flags=re.M) and "VSP_P0_TOPFIND_MW_WRAP_V1" not in s:
    s += "\n# VSP_P0_TOPFIND_MW_WRAP_V1\ntry:\n    application = _vsp__install_topfind_mw(application)\nexcept Exception:\n    pass\n"

p.write_text(s, encoding="utf-8")
print("[OK] installed TopFindings MW on application (no Flask route)")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sudo systemctl is-active --quiet vsp-ui-8910.service && echo "[OK] service active" || (echo "[ERR] service not active"; exit 2)

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251218_114312}"

echo "== [TEST] connect + body =="
rm -f /tmp/top.h /tmp/top.b
curl -sS -D /tmp/top.h -o /tmp/top.b "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5"
sed -n '1,15p' /tmp/top.h
cat /tmp/top.b; echo
python3 - <<'PY'
import json
j=json.load(open("/tmp/top.b","r",encoding="utf-8"))
print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"total=",j.get("total"),"reason=",j.get("reason"))
PY

echo "[DONE]"
