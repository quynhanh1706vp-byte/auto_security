#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need grep; need sed; need head; need curl

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_modv3_${TS}"
echo "[BACKUP] ${APP}.bak_modv3_${TS}"

echo "== [1] Write vsp_api_v3.py (Blueprint, idempotent) =="
cat > vsp_api_v3.py <<'PY'
# CIO v3 API module (Blueprint, idempotent)
import os, json, time, glob, re, mimetypes
from datetime import datetime
from pathlib import Path
from flask import Blueprint, request, jsonify, send_file

bp = Blueprint("vsp_v3", __name__, url_prefix="/api/vsp")

def _now_iso():
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"

def _safe_err(msg, code=400, **extra):
    j={"ok": False, "error": msg}
    j.update(extra)
    return jsonify(j), code

def _norm(x): return (x or "").strip()

def _guess_roots():
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
            p=Path(r)
            if r not in seen and p.exists():
                seen.add(r); out.append(r)
        except Exception:
            pass
    return out

def _parse_ts_from_rid(rid: str):
    m=re.search(r'(20\d{2})(\d{2})(\d{2})[_-]?(\d{2})(\d{2})(\d{2})', rid or "")
    if not m: return None
    try:
        dt=datetime(int(m.group(1)),int(m.group(2)),int(m.group(3)),
                    int(m.group(4)),int(m.group(5)),int(m.group(6)))
        return dt.timestamp()
    except Exception:
        return None

def _rid_latest():
    candidates=[]
    for root in _guess_roots():
        for pat in ("VSP_CI_20*","RUN_20*","RUN_VSP_*_20*"):
            for d in glob.glob(str(Path(root)/pat)):
                bn=Path(d).name
                try:
                    ts=_parse_ts_from_rid(bn) or Path(d).stat().st_mtime
                except Exception:
                    ts=_parse_ts_from_rid(bn) or 0
                candidates.append((float(ts or 0), bn))
    candidates.sort(reverse=True)
    return candidates[0][1] if candidates else ""

def _list_runs(limit=50, offset=0):
    items=[]
    for root in _guess_roots():
        for pat in ("VSP_CI_20*","RUN_20*","RUN_VSP_*_20*"):
            for d in glob.glob(str(Path(root)/pat)):
                rid=Path(d).name
                try:
                    ts=_parse_ts_from_rid(rid) or Path(d).stat().st_mtime
                except Exception:
                    ts=_parse_ts_from_rid(rid) or 0
                items.append({"rid": rid, "ts": float(ts or 0)})
    items.sort(key=lambda x: float(x.get("ts") or 0), reverse=True)
    out=[]
    for it in items[int(offset):int(offset)+int(limit)]:
        rid=it.get("rid",""); ts=float(it.get("ts") or 0)
        label=datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S") if ts>0 else rid
        out.append({"rid": rid, "label": label, "ts": ts})
    return out

def _resolve(rid: str, rel: str):
    rid=_norm(rid); rel=(rel or "").lstrip("/").strip()
    if not rid or not rel: return None
    for root in _guess_roots():
        base=Path(root)/rid
        if base.exists() and base.is_dir():
            p=base/rel
            if p.exists(): return str(p)
    return None

def _pick(rid: str, rels):
    for rel in rels:
        p=_resolve(rid, rel)
        if p: return p
    return None

def _kind_map(kind: str):
    kind=(kind or "").lower().strip()
    m={
      "gate": {"candidates":["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"], "download":"run_gate_summary.json","mimetype":"application/json"},
      "findings": {"candidates":["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"], "download":"findings.json","mimetype":"application/json"},
      "csv": {"candidates":["reports/findings_unified.csv","report/findings_unified.csv","findings_unified.csv"], "download":"findings.csv","mimetype":"text/csv"},
      "sarif": {"candidates":["reports/findings_unified.sarif","report/findings_unified.sarif","findings_unified.sarif"], "download":"findings.sarif","mimetype":"application/sarif+json"},
      "html": {"candidates":["reports/index.html","report/index.html","reports/checkmarx_like.html","report/checkmarx_like.html"], "download":"report.html","mimetype":"text/html"},
      "pdf": {"candidates":["reports/report.pdf","report/report.pdf","reports/vsp_report.pdf","report/vsp_report.pdf"], "download":"report.pdf","mimetype":"application/pdf"},
      "zip": {"candidates":["reports/report.zip","report/report.zip","reports/artifacts.zip","report/artifacts.zip"], "download":"artifacts.zip","mimetype":"application/zip"},
      "tgz": {"candidates":["reports/report.tgz","report/report.tgz","reports/artifacts.tgz","report/artifacts.tgz"], "download":"artifacts.tgz","mimetype":"application/gzip"},
    }
    return m.get(kind)

@bp.get("/rid_latest_v3")
def v3_rid_latest():
    rid=_rid_latest()
    return jsonify({"ok": True, "rid": rid, "ts": _now_iso()})

@bp.get("/runs_v3")
def v3_runs():
    try:
        limit=int(request.args.get("limit","50"))
        offset=int(request.args.get("offset","0"))
    except Exception:
        return _safe_err("bad limit/offset", 400)
    limit=max(1,min(limit,200)); offset=max(0,offset)
    latest=_rid_latest()
    runs=_list_runs(limit=200, offset=0)
    if latest:
        runs=[r for r in runs if r.get("rid")!=latest]
        ts=_parse_ts_from_rid(latest) or time.time()
        label=datetime.fromtimestamp(float(ts)).strftime("%Y-%m-%d %H:%M:%S")
        runs.insert(0, {"rid": latest, "label": label, "ts": float(ts)})
    total=len(runs)
    runs=runs[offset:offset+limit]
    return jsonify({"ok": True, "latest_rid": latest, "total": total, "limit": limit, "offset": offset, "runs": runs, "ts": _now_iso()})

@bp.get("/run_gate_v3")
def v3_run_gate():
    rid=_norm(request.args.get("rid")) or _rid_latest()
    p=_pick(rid, ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"])
    if not p: return _safe_err("gate summary not found", 404, rid=rid)
    try:
        j=json.loads(Path(p).read_text(encoding="utf-8", errors="replace"))
    except Exception as e:
        return _safe_err("gate summary unreadable", 500, rid=rid, detail=str(e))
    if isinstance(j, dict):
        for k in list(j.keys()):
            v=j.get(k)
            if isinstance(v,str) and (v.startswith("/") or v.startswith("file:")):
                j.pop(k, None)
    return jsonify({"ok": True, "rid": rid, "gate": j, "ts": _now_iso()})

@bp.get("/findings_v3")
def v3_findings():
    rid=_norm(request.args.get("rid")) or _rid_latest()
    fmt=(request.args.get("format") or "page").lower().strip()
    q=(request.args.get("q") or "").strip().lower()
    sev=(request.args.get("severity") or "").strip().upper()
    try:
        limit=int(request.args.get("limit","50"))
        offset=int(request.args.get("offset","0"))
    except Exception:
        return _safe_err("bad limit/offset", 400)
    limit=max(1,min(limit,500)); offset=max(0,offset)
    p=_pick(rid, ["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"])
    if not p: return _safe_err("findings not found", 404, rid=rid)
    if fmt in ("raw","file"):
        return send_file(p, as_attachment=False, mimetype="application/json", download_name="findings.json")
    try:
        data=json.loads(Path(p).read_text(encoding="utf-8", errors="replace"))
    except Exception as e:
        return _safe_err("findings unreadable", 500, rid=rid, detail=str(e))
    items = data.get("findings") if isinstance(data, dict) else data
    if not isinstance(items, list): items=[]
    def ok_item(it):
        if not isinstance(it, dict): return False
        if sev and (str(it.get("severity","")).upper()!=sev): return False
        if q:
            blob=(" ".join([str(it.get("title","")),str(it.get("tool","")),str(it.get("file","")),str(it.get("cwe","")),str(it.get("rule_id",""))])).lower()
            if q not in blob: return False
        return True
    filtered=[it for it in items if ok_item(it)]
    total=len(filtered)
    page=filtered[offset:offset+limit]
    for it in page:
        f=it.get("file")
        if isinstance(f,str) and f.startswith("/"):
            it["file"]=Path(f).name
    return jsonify({"ok": True, "rid": rid, "total": total, "limit": limit, "offset": offset, "items": page, "ts": _now_iso()})

@bp.get("/artifact_v3")
def v3_artifact():
    rid=_norm(request.args.get("rid")) or _rid_latest()
    kind=(request.args.get("kind") or "").lower().strip()
    m=_kind_map(kind)
    if not m: return _safe_err("unknown kind", 400, rid=rid, kind=kind)
    p=_pick(rid, m["candidates"])
    if not p: return _safe_err("artifact not found", 404, rid=rid, kind=kind)
    dn=m.get("download") or kind
    mt=m.get("mimetype") or (mimetypes.guess_type(dn)[0] or "application/octet-stream")
    as_att=(request.args.get("download")=="1")
    return send_file(p, as_attachment=as_att, mimetype=mt, download_name=dn)

@bp.get("/dashboard_v3")
def v3_dashboard():
    rid=_norm(request.args.get("rid")) or _rid_latest()
    gate_p=_pick(rid, ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"])
    gate={}
    if gate_p:
        try: gate=json.loads(Path(gate_p).read_text(encoding="utf-8", errors="replace"))
        except Exception: gate={}
    kpi={
        "rid": rid,
        "latest_rid": _rid_latest(),
        "severity_counts": (gate.get("severity_counts") or gate.get("counts") or {}) if isinstance(gate, dict) else {},
        "degraded": gate.get("degraded") if isinstance(gate, dict) else None,
    }
    runs=_list_runs(limit=30, offset=0)
    points=[]
    for r in runs[:20]:
        rr=r.get("rid","")
        gp=_pick(rr, ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"])
        if not gp: continue
        try: gj=json.loads(Path(gp).read_text(encoding="utf-8", errors="replace"))
        except Exception: continue
        sc=gj.get("severity_counts") or gj.get("counts") or {}
        total=sc.get("total") if isinstance(sc, dict) else None
        if total is None and isinstance(gj, dict):
            total=gj.get("total_findings") or gj.get("total")
        points.append({"rid": rr, "label": r.get("label") or rr, "total": int(total or 0), "ts": r.get("ts")})
    return jsonify({"ok": True, "rid": rid, "latest_rid": _rid_latest(), "kpi": kpi, "trend": points, "ts": _now_iso()})

def register_v3(app):
    # Absolutely idempotent
    if getattr(app, "blueprints", None) and "vsp_v3" in app.blueprints:
        return False
    app.register_blueprint(bp)
    return True
PY

echo "== [2] Patch vsp_demo_app.py to register v3 blueprint once =="
"$PY" - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="# === CIO V3 REGISTER (AUTO) ==="
if MARK in s:
    print("[OK] already has v3 register marker")
else:
    ins = "\n" + MARK + "\nfrom vsp_api_v3 import register_v3 as _register_v3\ntry:\n    _register_v3(app)\nexcept Exception:\n    pass\n"
    # insert right after app = Flask(...)
    m=re.search(r'(?m)^(?P<indent>\s*)app\s*=\s*Flask\([^\n]*\)\s*$', s)
    if not m:
        # fallback: after first occurrence of "app =" line
        m=re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)
    if not m:
        s = s.rstrip() + "\n" + ins + "\n"
        print("[WARN] app=Flask not found; appended register block at EOF")
    else:
        nl=s.find("\n", m.end())
        s = s[:nl+1] + ins + "\n" + s[nl+1:]
        print("[OK] inserted v3 register block after app=Flask")
    p.write_text(s, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile ok")
PY

echo "== [3] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [4] Smoke v3 endpoints =="
curl -fsS "$BASE/api/vsp/rid_latest_v3" | head -c 180; echo
curl -fsS "$BASE/api/vsp/runs_v3?limit=2" | head -c 220; echo
curl -fsS "$BASE/api/vsp/dashboard_v3" | head -c 220; echo
echo "[DONE] v3 blueprint live."
