#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_topfind_v5_${TS}"
echo "[BACKUP] ${W}.bak_topfind_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

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
    "import time",
    "import re",
    "import csv",
    "from datetime import datetime",
]:
    ensure_import(line)

marker = "VSP_P0_TOPFIND_GATEWAY_V5"

route_block = f"""
# {marker}
def _vsp__sev_weight(sev: str) -> int:
    m = {{"CRITICAL": 600, "HIGH": 500, "MEDIUM": 400, "LOW": 300, "INFO": 200, "TRACE": 100}}
    return m.get((sev or "").upper(), 0)

def _vsp__sanitize_path(pth: str) -> str:
    if not pth:
        return ""
    pth = (pth or "").replace("\\\\", "/")
    pth = re.sub(r'^/+', '', pth)
    parts = [x for x in pth.split("/") if x]
    return "/".join(parts[-4:]) if len(parts) > 4 else "/".join(parts)

def _vsp__candidate_run_roots():
    # keep consistent with your standard layouts
    return [
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]

def _vsp__find_run_dir_for_rid(rid: str) -> str:
    if not rid:
        return ""
    for root in _vsp__candidate_run_roots():
        d = os.path.join(root, rid)
        if os.path.isdir(d):
            return d
    # prefix match (latest mtime)
    best = ("", -1.0)
    for root in _vsp__candidate_run_roots():
        try:
            for d in glob.glob(os.path.join(root, rid + "*")):
                if not os.path.isdir(d):
                    continue
                mt = os.path.getmtime(d)
                if mt > best[1]:
                    best = (d, mt)
        except Exception:
            continue
    return best[0] or ""

def _vsp__has_any_source(run_dir: str) -> bool:
    if not run_dir:
        return False
    cand = [
        os.path.join(run_dir, "reports", "findings_unified.json"),
        os.path.join(run_dir, "findings_unified.json"),
        os.path.join(run_dir, "report", "findings_unified.json"),
        os.path.join(run_dir, "reports", "findings_unified.csv"),
        os.path.join(run_dir, "reports", "findings_unified.sarif"),
    ]
    for fp in cand:
        try:
            if os.path.isfile(fp) and os.path.getsize(fp) > 20:
                return True
        except Exception:
            pass
    return False

def _vsp__pick_latest_rid_with_sources() -> str:
    best = ("", -1.0)
    for root in _vsp__candidate_run_roots():
        try:
            if not os.path.isdir(root):
                continue
            for d in glob.glob(os.path.join(root, "VSP_*")):
                if not os.path.isdir(d):
                    continue
                if not _vsp__has_any_source(d):
                    continue
                mt = os.path.getmtime(d)
                name = os.path.basename(d)
                if mt > best[1]:
                    best = (name, mt)
        except Exception:
            continue
    return best[0] or ""

def _vsp__load_from_json(run_dir: str):
    for fp in [
        os.path.join(run_dir, "reports", "findings_unified.json"),
        os.path.join(run_dir, "findings_unified.json"),
        os.path.join(run_dir, "report", "findings_unified.json"),
    ]:
        try:
            if not os.path.isfile(fp) or os.path.getsize(fp) < 5:
                continue
            obj = json.load(open(fp, "r", encoding="utf-8"))
            if isinstance(obj, dict) and isinstance(obj.get("findings"), list):
                return obj.get("findings") or [], ""
            if isinstance(obj, list):
                return obj, ""
        except Exception as e:
            continue
    return None, "JSON_NOT_FOUND"

def _vsp__load_from_csv(run_dir: str):
    fp = os.path.join(run_dir, "reports", "findings_unified.csv")
    if not os.path.isfile(fp) or os.path.getsize(fp) < 5:
        return None, "CSV_NOT_FOUND"
    try:
        items = []
        with open(fp, "r", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            for row in r:
                if not row:
                    continue
                items.append({
                    "tool": row.get("tool") or row.get("scanner") or row.get("source"),
                    "severity": (row.get("severity") or "").upper(),
                    "title": row.get("title") or row.get("message") or row.get("name"),
                    "cwe": row.get("cwe") or row.get("cwe_id"),
                    "rule_id": row.get("rule_id") or row.get("check_id") or row.get("id"),
                    "file": row.get("file") or row.get("path") or "",
                    "line": row.get("line") or row.get("start_line") or row.get("line_start"),
                })
        return items, ""
    except Exception:
        return None, "CSV_PARSE_ERR"

def _vsp__load_from_sarif(run_dir: str):
    fp = os.path.join(run_dir, "reports", "findings_unified.sarif")
    if not os.path.isfile(fp) or os.path.getsize(fp) < 5:
        return None, "SARIF_NOT_FOUND"
    try:
        sar = json.load(open(fp, "r", encoding="utf-8"))
        runs = sar.get("runs") or []
        results = []
        for run in runs:
            for res in (run.get("results") or []):
                ruleId = res.get("ruleId") or res.get("rule") or res.get("id")
                msg = (res.get("message") or {}).get("text") if isinstance(res.get("message"), dict) else res.get("message")
                loc = ""
                line = None
                locs = res.get("locations") or []
                if locs:
                    pl = (locs[0].get("physicalLocation") or {})
                    art = (pl.get("artifactLocation") or {})
                    loc = art.get("uri") or ""
                    reg = (pl.get("region") or {})
                    line = reg.get("startLine") or reg.get("start_line")
                results.append({
                    "tool": (run.get("tool") or {}).get("driver", {}).get("name"),
                    "severity": "",  # sarif often lacks; keep empty
                    "title": msg,
                    "cwe": None,
                    "rule_id": ruleId,
                    "file": loc,
                    "line": line,
                })
        if not results:
            return None, "SARIF_NO_RESULTS"
        return results, ""
    except Exception:
        return None, "SARIF_PARSE_ERR"

def _vsp__normalize_findings(raw):
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

@app.route("/api/vsp/top_findings_v1", methods=["GET"], endpoint="vsp_top_findings_v1_gateway_v5")
def vsp_top_findings_v1_gateway_v5():
    # Always return a stable commercial contract (even if no data)
    rid_req = (request.args.get("rid") or "").strip()
    rid = rid_req
    try:
        limit = int(request.args.get("limit") or "5")
    except Exception:
        limit = 5
    if limit < 1: limit = 1
    if limit > 50: limit = 50

    def build_fail(reason: str, rid_used: str = ""):
        # keep backward-compatible keys too (err/has)
        return jsonify({
            "ok": False,
            "rid": (rid_used or rid_req or ""),
            "rid_requested": rid_req or None,
            "rid_used": rid_used or None,
            "total": 0,
            "items": [],
            "reason": reason,
            "err": reason,
            "has": ["json:findings_unified.json", "csv:reports/findings_unified.csv", "sarif:reports/findings_unified.sarif"],
        }), 200

    # 1) if requested rid has no source, fallback to latest rid with sources
    run_dir = _vsp__find_run_dir_for_rid(rid) if rid else ""
    if (not rid) or (not run_dir) or (not _vsp__has_any_source(run_dir)):
        rid2 = _vsp__pick_latest_rid_with_sources()
        if rid2:
            rid = rid2
            run_dir = _vsp__find_run_dir_for_rid(rid2)

    if not rid or not run_dir:
        return build_fail("NO_RUNS_OR_RID_NOT_FOUND")

    # 2) load in priority: json -> csv -> sarif
    raw, rj = _vsp__load_from_json(run_dir)
    if raw is None:
        raw, rc = _vsp__load_from_csv(run_dir)
        if raw is None:
            raw, rs = _vsp__load_from_sarif(run_dir)
            if raw is None:
                return build_fail("NO_USABLE_SOURCE", rid_used=rid)

    items = _vsp__normalize_findings(raw)
    return jsonify({
        "ok": True,
        "rid": rid,
        "rid_requested": rid_req or None,
        "rid_used": rid,
        "total": len(items),
        "items": items[:limit],
        "ts": datetime.utcnow().isoformat() + "Z",
    }), 200
# END {marker}
"""

if marker in s:
    # Replace existing block
    s = re.sub(
        r'#\s*' + re.escape(marker) + r'[\s\S]*?#\s*END\s*' + re.escape(marker),
        route_block.strip(),
        s,
        flags=re.M
    )
else:
    # Disable any existing decorators pointing to the same path to avoid conflicts
    lines = s.splitlines(True)
    out = []
    for ln in lines:
        if ln.lstrip().startswith("@app.route") and ("/api/vsp/top_findings_v1" in ln):
            out.append(ln.replace("/api/vsp/top_findings_v1", "/api/vsp/_disabled_top_findings_v1_legacy"))
        else:
            out.append(ln)
    s = "".join(out)

    # Insert before application export if possible
    m = re.search(r'^\s*application\s*=\s*', s, flags=re.M)
    if m:
        s = s[:m.start()] + "\n" + route_block + "\n" + s[m.start():]
    else:
        s = s + "\n" + route_block + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched wsgi_vsp_ui_gateway.py top_findings_v1 to V5 contract+fallback")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service || true
sudo systemctl is-active --quiet vsp-ui-8910.service && echo "[OK] service active" || echo "[WARN] service not active; check journalctl"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251218_114312}"

echo "== [TEST] top_findings_v1 headers+body =="
curl -sS -D /tmp/top.h -o /tmp/top.b "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" || true
sed -n '1,20p' /tmp/top.h
head -c 260 /tmp/top.b; echo

echo "== [TEST] parse contract =="
python3 - <<'PY'
import json
b=open("/tmp/top.b","rb").read().strip()
j=json.loads(b.decode("utf-8","replace")) if b else {}
print("ok=",j.get("ok"),"rid_req=",j.get("rid_requested"),"rid_used=",j.get("rid_used"),"total=",j.get("total"))
print("items=", len(j.get("items") or []))
if j.get("items"):
    it=j["items"][0]
    print("first=", it.get("severity"), (it.get("title") or "")[:90])
PY

echo "[DONE]"
