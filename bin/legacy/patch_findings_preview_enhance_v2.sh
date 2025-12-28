#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_findings_preview_v2_${TS}"
echo "[BACKUP] $F.bak_findings_preview_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_FINDINGS_PREVIEW_V2" in t:
    print("[OK] already installed")
    raise SystemExit(0)

# tìm def handler cũ nếu có
m = re.search(r"def\s+api_vsp_run_findings_preview_v1\s*\(\s*[^)]*\)\s*:\n", t)
if not m:
    print("[ERR] cannot find api_vsp_run_findings_preview_v1() in vsp_demo_app.py")
    raise SystemExit(1)

# replace whole function block (naive: from def line to next blank line + def/route)
start = m.start()
# cắt tới trước "def " tiếp theo ở cột 0
m2 = re.search(r"\n(?=def\s+\w+\s*\()", t[m.end():])
end = m.end() + (m2.start() if m2 else 0)

NEW = r'''
# === VSP_FINDINGS_PREVIEW_V2 ===
def api_vsp_run_findings_preview_v1(req_id):
    """
    GET /api/vsp/run_findings_preview_v1/<RID>?limit=50&offset=0&tool=&severity=&q=
    - returns small preview list for Data Source tab
    """
    import json, csv
    from pathlib import Path
    from flask import request, jsonify

    rid = (req_id or "").strip()
    limit = int(request.args.get("limit", "50") or "50")
    offset = int(request.args.get("offset", "0") or "0")
    limit = max(1, min(limit, 200))
    offset = max(0, offset)

    f_tool = (request.args.get("tool","") or "").strip().lower()
    f_sev  = (request.args.get("severity","") or "").strip().upper()
    q      = (request.args.get("q","") or "").strip().lower()

    # resolve run_dir (prefer existing resolver if present)
    _resolve = globals().get("_vsp_resolve_ci_run_dir", None)
    if _resolve is None:
        def _resolve(_rid: str):
            key = (_rid or "").strip()
            if key.startswith("RUN_"):
                key = key[len("RUN_"):]
            bases = [
                "/home/test/Data/SECURITY-10-10-v4/out_ci",
                "/home/test/Data/SECURITY_BUNDLE/out",
                "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
            ]
            for b in bases:
                d = Path(b) / key
                if d.is_dir():
                    return d
            return None

    run_dir = _resolve(rid)
    if not run_dir:
        return jsonify({
            "ok": False, "status":"ERROR", "final": True, "http_code": 404,
            "error":"RUN_DIR_NOT_FOUND", "rid": rid,
            "has_findings": None, "total": None, "items": None,
        }), 404

    run_dir = Path(run_dir)

    # candidate files
    cands = [
        run_dir/"reports"/"findings_unified.json",
        run_dir/"findings_unified.json",
        run_dir/"reports"/"findings.json",
        run_dir/"findings.json",
        run_dir/"reports"/"findings_unified.sarif",
        run_dir/"findings_unified.sarif",
        run_dir/"reports"/"findings_unified.csv",
        run_dir/"findings_unified.csv",
    ]

    src = None
    for fp in cands:
        try:
            if fp.is_file() and fp.stat().st_size > 0:
                src = fp
                break
        except Exception:
            pass

    if not src:
        return jsonify({
            "ok": True, "status":"OK", "final": True, "http_code": 200,
            "rid": rid, "run_dir": str(run_dir),
            "has_findings": False, "total": 0,
            "warning": "findings_file_not_found",
            "file": None, "items": [],
        })

    def norm_item(x):
        # best-effort normalize fields
        if not isinstance(x, dict):
            return {"title": str(x)}
        out = {}
        out["tool"] = (x.get("tool") or x.get("scanner") or x.get("engine") or "").strip()
        out["severity"] = (x.get("severity") or x.get("level") or x.get("priority") or "").strip().upper()
        out["title"] = (x.get("title") or x.get("message") or x.get("name") or x.get("rule") or "").strip()
        out["rule_id"] = (x.get("rule_id") or x.get("check_id") or x.get("rule") or "").strip()
        out["file"] = (x.get("file") or x.get("path") or x.get("filename") or "").strip()
        out["line"] = x.get("line") or x.get("start_line") or x.get("line_number") or None
        out["cwe"] = x.get("cwe") or x.get("cwe_id") or None
        out["url"] = (x.get("url") or x.get("target") or "").strip()
        # raw keep (small)
        return out

    items = []
    warning = None

    try:
        if src.suffix.lower() == ".json":
            data = json.loads(src.read_text(encoding="utf-8", errors="ignore"))
            if isinstance(data, dict):
                # common shapes
                if "items" in data and isinstance(data["items"], list):
                    items = data["items"]
                elif "findings" in data and isinstance(data["findings"], list):
                    items = data["findings"]
                else:
                    # if dict of lists -> flatten
                    for v in data.values():
                        if isinstance(v, list):
                            items.extend(v)
            elif isinstance(data, list):
                items = data
        elif src.suffix.lower() == ".sarif":
            data = json.loads(src.read_text(encoding="utf-8", errors="ignore"))
            runs = (data.get("runs") or [])
            for r in runs:
                tool = (((r.get("tool") or {}).get("driver") or {}).get("name") or "SARIF").strip()
                results = r.get("results") or []
                for rs in results:
                    sev = ""
                    props = rs.get("properties") or {}
                    sev = (props.get("severity") or props.get("level") or "").upper()
                    rule_id = (rs.get("ruleId") or "").strip()
                    msg = (((rs.get("message") or {}).get("text")) or "").strip()
                    locs = (rs.get("locations") or [])
                    fp = ""
                    ln = None
                    if locs:
                        pl = ((locs[0].get("physicalLocation") or {}).get("artifactLocation") or {}).get("uri") or ""
                        fp = str(pl)
                        reg = ((locs[0].get("physicalLocation") or {}).get("region") or {})
                        ln = reg.get("startLine") or None
                    items.append({
                        "tool": tool, "severity": sev, "title": msg, "rule_id": rule_id,
                        "file": fp, "line": ln
                    })
        else:
            # CSV
            with src.open("r", encoding="utf-8", errors="ignore", newline="") as f:
                rd = csv.DictReader(f)
                for row in rd:
                    items.append(row)
    except Exception as e:
        warning = f"parse_error:{type(e).__name__}"
        items = []

    normed = [norm_item(x) for x in items]

    # filters
    def hit(it):
        if f_tool and (it.get("tool","").lower() != f_tool):
            return False
        if f_sev and (it.get("severity","").upper() != f_sev):
            return False
        if q:
            blob = " ".join([str(it.get(k,"") or "") for k in ("tool","severity","title","rule_id","file","url","cwe")]).lower()
            return q in blob
        return True

    filtered = [it for it in normed if hit(it)]
    total = len(filtered)
    page = filtered[offset:offset+limit]

    return jsonify({
        "ok": True, "status":"OK", "final": True, "http_code": 200,
        "rid": rid, "run_dir": str(run_dir),
        "has_findings": total > 0,
        "warning": warning,
        "file": str(src),
        "total": total,
        "limit": limit,
        "offset": offset,
        "filters": {"tool": f_tool or None, "severity": f_sev or None, "q": q or None},
        "items": page,
    })
# === /VSP_FINDINGS_PREVIEW_V2 ===
'''

t2 = t[:start] + NEW + t[end:]
p.write_text(t2, encoding="utf-8")
print("[OK] patched api_vsp_run_findings_preview_v1 (V2)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"
echo "[DONE] restart 8910"
