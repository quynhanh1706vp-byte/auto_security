#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_findprev_${TS}"
echo "[BACKUP] $F.bak_findprev_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG="VSP_GATEWAY_FINDINGS_PREVIEW_V1"
if TAG in t or "/api/vsp/run_findings_preview_v1/" in t:
    print("[OK] findings_preview already installed, skip")
    raise SystemExit(0)

BLOCK = r'''

# === VSP_GATEWAY_FINDINGS_PREVIEW_V1 ===
def _vsp_install_findings_preview_v1(_app):
    try:
        from flask import request, jsonify
    except Exception:
        return
    import json, csv
    from pathlib import Path

    if _app is None or not hasattr(_app, "route"):
        return
    if getattr(_app, "_vsp_findings_preview_v1_installed", False):
        return
    setattr(_app, "_vsp_findings_preview_v1_installed", True)

    _resolve = globals().get("_vsp_resolve_ci_run_dir", None)
    if _resolve is None:
        def _resolve(rid: str):
            key = (rid or "").strip()
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

    def _norm(x):
        return (x or "").strip()

    def _pick_fields(rec: dict):
        # normalize common fields across tools
        return {
            "severity": rec.get("severity") or rec.get("sev") or rec.get("level") or "",
            "tool": rec.get("tool") or rec.get("source") or "",
            "rule_id": rec.get("rule_id") or rec.get("check_id") or rec.get("id") or "",
            "title": rec.get("title") or rec.get("message") or rec.get("name") or "",
            "file": rec.get("file") or rec.get("path") or rec.get("filename") or "",
            "line": rec.get("line") or rec.get("start_line") or rec.get("startLine") or "",
            "cwe": rec.get("cwe") or rec.get("cwe_id") or "",
        }

    def _load_json_findings(fp: Path):
        obj = json.loads(fp.read_text(encoding="utf-8", errors="ignore"))
        if isinstance(obj, dict):
            # common: {"findings":[...]} or {"items":[...]}
            for k in ("findings","items","results","data"):
                if k in obj and isinstance(obj[k], list):
                    return obj[k]
            # or already normalized dict -> wrap
            return [obj]
        if isinstance(obj, list):
            return obj
        return []

    def _load_csv_findings(fp: Path):
        rows = []
        with fp.open("r", encoding="utf-8", errors="ignore", newline="") as f:
            r = csv.DictReader(f)
            for row in r:
                rows.append(row)
        return rows

    def _match(rec: dict, sevs:set, tools:set, search:str):
        s = search.lower().strip() if search else ""
        if sevs:
            sev = str(rec.get("severity","")).upper()
            if sev not in sevs:
                return False
        if tools:
            tool = str(rec.get("tool","")).upper()
            if tool not in tools:
                return False
        if s:
            hay = " ".join([
                str(rec.get("title","")),
                str(rec.get("rule_id","")),
                str(rec.get("file","")),
                str(rec.get("cwe","")),
                str(rec.get("tool","")),
                str(rec.get("severity","")),
            ]).lower()
            if s not in hay:
                return False
        return True

    @_app.route("/api/vsp/run_findings_preview_v1/<rid>", methods=["GET"])
    def api_vsp_run_findings_preview_v1(rid):
        limit = int(request.args.get("limit","200") or "200")
        limit = max(1, min(limit, 2000))
        page = int(request.args.get("page","1") or "1")
        page = max(1, page)

        sevs_q = _norm(request.args.get("sev",""))
        tools_q = _norm(request.args.get("tool",""))
        search = _norm(request.args.get("search",""))

        sevs = set([x.strip().upper() for x in sevs_q.split(",") if x.strip()]) if sevs_q else set()
        tools = set([x.strip().upper() for x in tools_q.split(",") if x.strip()]) if tools_q else set()

        run_dir = _resolve(rid)
        if not run_dir:
            return jsonify(ok=False, error="run_not_found", rid=rid), 404

        run_dir = Path(run_dir)
        cand = [
            run_dir / "findings_unified.json",
            run_dir / "reports" / "findings_unified.json",
            run_dir / "findings_unified.csv",
            run_dir / "reports" / "findings_unified.csv",
        ]
        fp = next((x for x in cand if x.is_file() and x.stat().st_size>0), None)
        if not fp:
            return jsonify(ok=False, error="findings_file_not_found", rid=rid, run_dir=str(run_dir)), 404

        try:
            if fp.suffix.lower() == ".json":
                raw = _load_json_findings(fp)
            else:
                raw = _load_csv_findings(fp)
        except Exception as e:
            return jsonify(ok=False, error="findings_parse_error", detail=str(e), file=str(fp)), 500

        # normalize + filter
        normed = []
        for r in raw:
            if not isinstance(r, dict):
                continue
            rec = _pick_fields(r)
            if _match(rec, sevs, tools, search):
                normed.append(rec)

        total = len(normed)
        start = (page-1)*limit
        end = start + limit
        items = normed[start:end]

        # helpful facets
        sev_counts = {}
        tool_counts = {}
        for rec in normed[:5000]:
            sv = str(rec.get("severity","")).upper() or "UNKNOWN"
            tl = str(rec.get("tool","")).upper() or "UNKNOWN"
            sev_counts[sv] = sev_counts.get(sv, 0) + 1
            tool_counts[tl] = tool_counts.get(tl, 0) + 1

        return jsonify(
            ok=True,
            rid=rid,
            run_dir=str(run_dir),
            file=str(fp),
            page=page,
            limit=limit,
            total=total,
            items=items,
            facets={"severity": sev_counts, "tool": tool_counts},
        )
# === /VSP_GATEWAY_FINDINGS_PREVIEW_V1 ===

try:
    _APP = globals().get("application") or globals().get("app")
    _vsp_install_findings_preview_v1(_APP)
except Exception:
    pass
'''
p.write_text(t + "\n" + BLOCK + "\n", encoding="utf-8")
print("[OK] appended findings_preview_v1 route installer")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"

bin/restart_8910_nosudo_force_v1.sh
echo "[DONE] findings_preview endpoint ready."
