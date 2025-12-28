#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

W="wsgi_vsp_ui_gateway.py"
B="/home/test/Data/SECURITY_BUNDLE/ui/wsgi_vsp_ui_gateway.py.bak_topfind_v5b_20251223_184513"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
[ -f "$B" ] || { echo "[ERR] missing backup $B"; echo "Run: ls -1 wsgi_vsp_ui_gateway.py.bak_topfind_v5b_* | tail"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_before_v5c_${TS}"
echo "[BACKUP] ${W}.bak_before_v5c_${TS}"

# Restore from known-good backup to avoid indentation corruption
cp -f "$B" "$W"
echo "[OK] restored $W from $B"

python3 - <<'PY'
from pathlib import Path
import re

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

for line in ["import os","import json","import glob","import re","import csv","from datetime import datetime"]:
    ensure_import(line)

marker = "VSP_P0_TOPFIND_GATEWAY_V5C"

new_block = r'''
# VSP_P0_TOPFIND_GATEWAY_V5C
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

def _vsp__find_run_dir_for_rid(rid: str) -> str:
    if not rid:
        return ""
    for root in _vsp__candidate_run_roots():
        d = os.path.join(root, rid)
        if os.path.isdir(d):
            return d
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
                return (obj.get("findings") or []), ""
            if isinstance(obj, list):
                return obj, ""
        except Exception:
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

@app.route("/api/vsp/top_findings_v1", methods=["GET"], endpoint="vsp_top_findings_v1_gateway_v5c")
def vsp_top_findings_v1_gateway_v5c():
    rid_req = (request.args.get("rid") or "").strip()
    rid = rid_req
    try:
        limit = int(request.args.get("limit") or "5")
    except Exception:
        limit = 5
    if limit < 1: limit = 1
    if limit > 50: limit = 50

    def fail(reason: str, rid_used: str = ""):
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

    run_dir = _vsp__find_run_dir_for_rid(rid) if rid else ""
    if (not rid) or (not run_dir) or (not _vsp__has_any_source(run_dir)):
        rid2 = _vsp__pick_latest_rid_with_sources()
        if rid2:
            rid = rid2
            run_dir = _vsp__find_run_dir_for_rid(rid2)

    if not rid or not run_dir:
        return fail("NO_RUNS_OR_RID_NOT_FOUND")

    raw, rj = _vsp__load_from_json(run_dir)
    if raw is None:
        raw, rc = _vsp__load_from_csv(run_dir)
        if raw is None:
            return fail("NO_USABLE_SOURCE", rid_used=rid)

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
# END VSP_P0_TOPFIND_GATEWAY_V5C
'''

# 1) disable any existing decorators for this path (avoid double mapping)
lines = s.splitlines(True)
out = []
for ln in lines:
    if ln.lstrip().startswith("@app.route") and ("/api/vsp/top_findings_v1" in ln):
        out.append(ln.replace("/api/vsp/top_findings_v1", "/api/vsp/_disabled_top_findings_v1_legacy"))
    else:
        out.append(ln)
s = "".join(out)

# 2) insert our block at TOP-LEVEL by replacing the existing route block if present, else append to file end
if marker in s:
    s = re.sub(r'#\s*VSP_P0_TOPFIND_GATEWAY_V5C[\s\S]*?#\s*END\s*VSP_P0_TOPFIND_GATEWAY_V5C',
               new_block.strip(), s, flags=re.M)
else:
    s = s.rstrip() + "\n\n" + new_block.strip() + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] replaced/added v5c route safely at file end")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"
