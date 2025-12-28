#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need head

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_cio_v3_fixformat_${TS}"
echo "[BACKUP] ${APP}.bak_cio_v3_fixformat_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "### === CIO API v3 (AUTO) ==="
END  = "### === END CIO API v3 (AUTO) ==="

block = textwrap.dedent(r'''
### === CIO API v3 (AUTO) ===
# CIO-clean API v3: FE must NOT know internal file paths.
# Debug is OFF by default.

import os, json, time, mimetypes, glob, re
from datetime import datetime
from pathlib import Path as _Path
from flask import request, jsonify, send_file

def _v3_norm_rid(x):
    return (x or "").strip()

def _v3_now_iso():
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"

def _v3_safe_err(msg, code=400, **extra):
    j = {"ok": False, "error": msg}
    j.update(extra)
    return jsonify(j), code

def _v3_guess_roots():
    env = os.environ.get("VSP_RUN_ROOTS") or os.environ.get("VSP_OUT_ROOTS") or ""
    roots = [r.strip() for r in env.split(":") if r.strip()]
    roots += [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
    ]
    seen=set(); out=[]
    for r in roots:
        try:
            if r not in seen and _Path(r).exists():
                seen.add(r); out.append(r)
        except Exception:
            pass
    return out

def _v3_parse_ts_from_rid(rid: str):
    m = re.search(r'(20\d{2})(\d{2})(\d{2})[_-]?(\d{2})(\d{2})(\d{2})', rid or "")
    if not m:
        return None
    try:
        dt = datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                      int(m.group(4)), int(m.group(5)), int(m.group(6)))
        return dt.timestamp()
    except Exception:
        return None

def _v3_rid_latest():
    roots = _v3_guess_roots()
    candidates=[]
    for root in roots:
        for pat in ("VSP_CI_20*", "RUN_20*", "RUN_VSP_*_20*"):
            for d in glob.glob(str(_Path(root) / pat)):
                bn = _Path(d).name
                try:
                    ts = _v3_parse_ts_from_rid(bn) or _Path(d).stat().st_mtime
                except Exception:
                    ts = _v3_parse_ts_from_rid(bn) or 0
                candidates.append((float(ts or 0), bn))
    candidates.sort(reverse=True)
    return candidates[0][1] if candidates else ""

def _v3_list_runs_raw(limit=50, offset=0):
    roots=_v3_guess_roots()
    items=[]
    for root in roots:
        for pat in ("VSP_CI_20*", "RUN_20*", "RUN_VSP_*_20*"):
            for d in glob.glob(str(_Path(root) / pat)):
                rid = _Path(d).name
                try:
                    ts = _v3_parse_ts_from_rid(rid) or _Path(d).stat().st_mtime
                except Exception:
                    ts = _v3_parse_ts_from_rid(rid) or 0
                items.append({"rid": rid, "ts": float(ts or 0)})
    items.sort(key=lambda x: float(x.get("ts") or 0), reverse=True)
    out=[]
    for it in items[int(offset):int(offset)+int(limit)]:
        rid=it.get("rid","")
        ts=float(it.get("ts") or 0)
        label=datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S") if ts>0 else rid
        out.append({"rid": rid, "label": label, "ts": ts})
    return out

def _v3_resolve_run_file(rid: str, rel: str):
    rid=_v3_norm_rid(rid)
    rel=(rel or "").lstrip("/").strip()
    if not rid or not rel:
        return None
    for root in _v3_guess_roots():
        base = _Path(root) / rid
        if base.exists() and base.is_dir():
            pth = base / rel
            if pth.exists():
                return str(pth)
    return None

def _v3_pick_first_existing(rid: str, rel_paths):
    for rel in rel_paths:
        pth=_v3_resolve_run_file(rid, rel)
        if pth:
            return pth
    return None

def _v3_kind_map(kind: str):
    kind=(kind or "").lower().strip()
    m = {
        "gate": {"candidates": ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"],
                 "download": "run_gate_summary.json", "mimetype": "application/json"},
        "findings": {"candidates": ["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"],
                     "download": "findings.json", "mimetype": "application/json"},
        "csv": {"candidates": ["reports/findings_unified.csv","report/findings_unified.csv","findings_unified.csv"],
                "download": "findings.csv", "mimetype": "text/csv"},
        "sarif": {"candidates": ["reports/findings_unified.sarif","report/findings_unified.sarif","findings_unified.sarif"],
                  "download": "findings.sarif", "mimetype": "application/sarif+json"},
        "html": {"candidates": ["reports/index.html","report/index.html","reports/checkmarx_like.html","report/checkmarx_like.html"],
                 "download": "report.html", "mimetype": "text/html"},
        "pdf": {"candidates": ["reports/report.pdf","report/report.pdf","reports/vsp_report.pdf","report/vsp_report.pdf"],
                "download": "report.pdf", "mimetype": "application/pdf"},
        "zip": {"candidates": ["reports/report.zip","report/report.zip","reports/artifacts.zip","report/artifacts.zip"],
                "download": "artifacts.zip", "mimetype": "application/zip"},
        "tgz": {"candidates": ["reports/report.tgz","report/report.tgz","reports/artifacts.tgz","report/artifacts.tgz"],
                "download": "artifacts.tgz", "mimetype": "application/gzip"},
    }
    return m.get(kind)

@app.get("/api/vsp/rid_latest_v3")
def api_vsp_rid_latest_v3():
    rid=_v3_rid_latest()
    return jsonify({"ok": True, "rid": rid, "ts": _v3_now_iso()})

@app.get("/api/vsp/runs_v3")
def api_vsp_runs_v3():
    try:
        limit=int(request.args.get("limit","50"))
        offset=int(request.args.get("offset","0"))
    except Exception:
        return _v3_safe_err("bad limit/offset", 400)
    limit=max(1, min(limit, 200))
    offset=max(0, offset)
    runs=_v3_list_runs_raw(limit=200, offset=0)
    latest=_v3_rid_latest()
    if latest:
        runs=[r for r in runs if r.get("rid") != latest]
        ts=_v3_parse_ts_from_rid(latest) or time.time()
        label=datetime.fromtimestamp(float(ts)).strftime("%Y-%m-%d %H:%M:%S")
        runs.insert(0, {"rid": latest, "label": label, "ts": float(ts)})
    total=len(runs)
    runs=runs[offset:offset+limit]
    return jsonify({"ok": True, "latest_rid": latest, "total": total, "limit": limit, "offset": offset, "runs": runs, "ts": _v3_now_iso()})

@app.get("/api/vsp/run_gate_v3")
def api_vsp_run_gate_v3():
    rid=_v3_norm_rid(request.args.get("rid")) or _v3_rid_latest()
    pth=_v3_pick_first_existing(rid, ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"])
    if not pth:
        return _v3_safe_err("gate summary not found", 404, rid=rid)
    try:
        j=json.loads(_Path(pth).read_text(encoding="utf-8", errors="replace"))
    except Exception as e:
        return _v3_safe_err("gate summary unreadable", 500, rid=rid, detail=str(e))
    # scrub absolute path-like fields
    if isinstance(j, dict):
        for k in list(j.keys()):
            v=j.get(k)
            if isinstance(v,str) and (v.startswith("/") or v.startswith("file:")):
                j.pop(k, None)
    return jsonify({"ok": True, "rid": rid, "gate": j, "ts": _v3_now_iso()})

@app.get("/api/vsp/findings_v3")
def api_vsp_findings_v3():
    rid=_v3_norm_rid(request.args.get("rid")) or _v3_rid_latest()
    fmt=(request.args.get("format") or "page").lower().strip()
    q=(request.args.get("q") or "").strip().lower()
    sev=(request.args.get("severity") or "").strip().upper()
    try:
        limit=int(request.args.get("limit","50"))
        offset=int(request.args.get("offset","0"))
    except Exception:
        return _v3_safe_err("bad limit/offset", 400)
    limit=max(1, min(limit, 500))
    offset=max(0, offset)

    pth=_v3_pick_first_existing(rid, ["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"])
    if not pth:
        return _v3_safe_err("findings not found", 404, rid=rid)

    if fmt in ("raw","file"):
        return send_file(pth, as_attachment=False, mimetype="application/json", download_name="findings.json")

    try:
        data=json.loads(_Path(pth).read_text(encoding="utf-8", errors="replace"))
    except Exception as e:
        return _v3_safe_err("findings unreadable", 500, rid=rid, detail=str(e))

    items = data.get("findings") if isinstance(data, dict) else data
    if not isinstance(items, list):
        items=[]

    def ok_item(it):
        if not isinstance(it, dict):
            return False
        if sev and (str(it.get("severity","")).upper()!=sev):
            return False
        if q:
            blob=(" ".join([str(it.get("title","")), str(it.get("tool","")), str(it.get("file","")), str(it.get("cwe","")), str(it.get("rule_id",""))])).lower()
            if q not in blob:
                return False
        return True

    filtered=[it for it in items if ok_item(it)]
    total=len(filtered)
    page=filtered[offset:offset+limit]

    for it in page:
        f=it.get("file")
        if isinstance(f,str) and f.startswith("/"):
            it["file"]=_Path(f).name

    return jsonify({"ok": True, "rid": rid, "total": total, "limit": limit, "offset": offset, "items": page, "ts": _v3_now_iso()})

@app.get("/api/vsp/artifact_v3")
def api_vsp_artifact_v3():
    rid=_v3_norm_rid(request.args.get("rid")) or _v3_rid_latest()
    kind=(request.args.get("kind") or "").lower().strip()
    m=_v3_kind_map(kind)
    if not m:
        return _v3_safe_err("unknown kind", 400, rid=rid, kind=kind)
    pth=_v3_pick_first_existing(rid, m["candidates"])
    if not pth:
        return _v3_safe_err("artifact not found", 404, rid=rid, kind=kind)
    download_name=m.get("download") or kind
    mt=m.get("mimetype") or (mimetypes.guess_type(download_name)[0] or "application/octet-stream")
    as_att = (request.args.get("download") == "1")
    return send_file(pth, as_attachment=as_att, mimetype=mt, download_name=download_name)

@app.get("/api/vsp/dashboard_v3")
def api_vsp_dashboard_v3():
    rid=_v3_norm_rid(request.args.get("rid")) or _v3_rid_latest()
    gate_pth=_v3_pick_first_existing(rid, ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"])
    gate={}
    if gate_pth:
        try:
            gate=json.loads(_Path(gate_pth).read_text(encoding="utf-8", errors="replace"))
        except Exception:
            gate={}
    kpi={
        "rid": rid,
        "latest_rid": _v3_rid_latest(),
        "severity_counts": gate.get("severity_counts") or gate.get("counts") or {},
        "degraded": gate.get("degraded") if isinstance(gate, dict) else None,
    }
    runs=_v3_list_runs_raw(limit=30, offset=0)
    points=[]
    for r in runs[:20]:
        rr=r.get("rid","")
        gp=_v3_pick_first_existing(rr, ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"])
        if not gp:
            continue
        try:
            gj=json.loads(_Path(gp).read_text(encoding="utf-8", errors="replace"))
        except Exception:
            continue
        sc=gj.get("severity_counts") or gj.get("counts") or {}
        total=sc.get("total") if isinstance(sc, dict) else None
        if total is None and isinstance(gj, dict):
            total=gj.get("total_findings") or gj.get("total")
        points.append({"rid": rr, "label": r.get("label") or rr, "total": int(total or 0), "ts": r.get("ts")})
    top=[]
    fp=_v3_pick_first_existing(rid, ["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"])
    if fp:
        try:
            data=json.loads(_Path(fp).read_text(encoding="utf-8", errors="replace"))
            items = data.get("findings") if isinstance(data, dict) else data
            if isinstance(items, list):
                rank={"CRITICAL":5,"HIGH":4,"MEDIUM":3,"LOW":2,"INFO":1,"TRACE":0}
                items=[it for it in items if isinstance(it, dict)]
                items.sort(key=lambda it: rank.get(str(it.get("severity","")).upper(), -1), reverse=True)
                for it in items[:10]:
                    f=it.get("file")
                    if isinstance(f,str) and f.startswith("/"):
                        it["file"]=_Path(f).name
                    top.append(it)
        except Exception:
            top=[]
    return jsonify({"ok": True, "rid": rid, "latest_rid": _v3_rid_latest(), "kpi": kpi, "trend": points, "top_findings": top, "ts": _v3_now_iso()})

### === END CIO API v3 (AUTO) ===
''').strip("\n") + "\n"

if MARK in s and END in s:
    # replace existing block
    s2 = re.sub(rf'{re.escape(MARK)}.*?{re.escape(END)}\n?', block, s, flags=re.S)
    if s2 == s:
        raise SystemExit("[ERR] found markers but replacement failed")
    s = s2
    print("[OK] replaced existing CIO v3 block")
elif MARK in s and END not in s:
    raise SystemExit("[ERR] found MARK without END (file previously half-injected). Restore from backup and rerun.")
else:
    # insert before main guard or append
    m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
    if m:
        s = s[:m.start()] + "\n\n" + block + "\n" + s[m.start():]
        print("[OK] inserted CIO v3 block before __main__")
    else:
        s = s.rstrip() + "\n\n" + block
        print("[OK] appended CIO v3 block at EOF")

p.write_text(s, encoding="utf-8")
py_compile.compile("vsp_demo_app.py", doraise=True)
print("[OK] py_compile ok")
PY

echo "== [RESTART] restart service if exists =="
if command -v systemctl >/dev/null 2>&1; then
  if systemctl status "$SVC" >/dev/null 2>&1; then
    sudo systemctl restart "$SVC"
    echo "[OK] restarted $SVC"
  else
    echo "[WARN] $SVC not found/running; skip restart"
  fi
else
  echo "[WARN] systemctl missing; skip restart"
fi

echo "== [SMOKE] CIO v3 endpoints =="
curl -fsS "$BASE/api/vsp/rid_latest_v3" | head -c 250; echo
curl -fsS "$BASE/api/vsp/runs_v3?limit=3&offset=0" | head -c 250; echo
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_v3" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] latest RID=$RID"
curl -fsS "$BASE/api/vsp/dashboard_v3?rid=$RID" | head -c 250; echo
curl -fsS "$BASE/api/vsp/run_gate_v3?rid=$RID" | head -c 250; echo
curl -fsS "$BASE/api/vsp/findings_v3?rid=$RID&limit=1&offset=0" | head -c 250; echo

echo
echo "[DONE] backend v3 ready. Next: patch FE safely (downloads) after /runs click-through."
