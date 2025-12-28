#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need awk; need head; need curl

echo "== [0] Service ExecStart / unit info =="
systemctl show "$SVC" -p FragmentPath -p ExecStart -p MainPID -p ActiveState -p SubState || true
echo
echo "== [1] systemctl status (last lines) =="
systemctl status "$SVC" --no-pager -l | tail -n 120 || true
echo
echo "== [2] journalctl (recent) =="
journalctl -xeu "$SVC" --no-pager | tail -n 160 || true
echo

echo "== [3] Detect backend entry file from ExecStart =="
EXE="$(systemctl show "$SVC" -p ExecStart --value || true)"
echo "[INFO] ExecStart=$EXE"

TARGET=""
# Common patterns:
#  - ... gunicorn ... wsgi_vsp_ui_gateway:app
#  - ... python3 vsp_demo_app.py
if echo "$EXE" | grep -qE 'wsgi_vsp_ui_gateway:app|wsgi_vsp_ui_gateway\.py'; then
  TARGET="wsgi_vsp_ui_gateway.py"
elif echo "$EXE" | grep -qE 'vsp_demo_app\.py'; then
  TARGET="vsp_demo_app.py"
else
  # heuristic: find "something.py" in ExecStart
  TARGET="$(echo "$EXE" | grep -oE '[A-Za-z0-9_./-]+\.py' | head -n 1 || true)"
  [ -z "${TARGET:-}" ] && TARGET="wsgi_vsp_ui_gateway.py"
fi

if [ ! -f "$TARGET" ]; then
  echo "[WARN] detected target '$TARGET' missing; fallback to wsgi_vsp_ui_gateway.py"
  TARGET="wsgi_vsp_ui_gateway.py"
fi

echo "[INFO] backend target file => $TARGET"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TARGET" "${TARGET}.bak_cio_v3_inject_${TS}"
echo "[BACKUP] ${TARGET}.bak_cio_v3_inject_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile, sys

target = Path(sys.argv[1])
s = target.read_text(encoding="utf-8", errors="replace")

MARK="### === CIO API v3 (AUTO) ==="
END ="### === END CIO API v3 (AUTO) ==="

block = textwrap.dedent(r'''
### === CIO API v3 (AUTO) ===
# CIO-clean API v3: FE must NOT know internal file paths.

import os, json, time, mimetypes, glob, re
from datetime import datetime
from pathlib import Path as _Path
from flask import request, jsonify, send_file

def _v3_norm_rid(x): return (x or "").strip()
def _v3_now_iso(): return datetime.utcnow().isoformat(timespec="seconds")+"Z"
def _v3_safe_err(msg, code=400, **extra):
    j={"ok": False, "error": msg}; j.update(extra); return jsonify(j), code

def _v3_guess_roots():
    env=os.environ.get("VSP_RUN_ROOTS") or os.environ.get("VSP_OUT_ROOTS") or ""
    roots=[r.strip() for r in env.split(":") if r.strip()]
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
    m=re.search(r'(20\d{2})(\d{2})(\d{2})[_-]?(\d{2})(\d{2})(\d{2})', rid or "")
    if not m: return None
    try:
        dt=datetime(int(m.group(1)),int(m.group(2)),int(m.group(3)),
                    int(m.group(4)),int(m.group(5)),int(m.group(6)))
        return dt.timestamp()
    except Exception:
        return None

def _v3_rid_latest():
    roots=_v3_guess_roots()
    candidates=[]
    for root in roots:
        for pat in ("VSP_CI_20*","RUN_20*","RUN_VSP_*_20*"):
            for d in glob.glob(str(_Path(root)/pat)):
                bn=_Path(d).name
                try:
                    ts=_v3_parse_ts_from_rid(bn) or _Path(d).stat().st_mtime
                except Exception:
                    ts=_v3_parse_ts_from_rid(bn) or 0
                candidates.append((float(ts or 0), bn))
    candidates.sort(reverse=True)
    return candidates[0][1] if candidates else ""

def _v3_list_runs_raw(limit=50, offset=0):
    roots=_v3_guess_roots()
    items=[]
    for root in roots:
        for pat in ("VSP_CI_20*","RUN_20*","RUN_VSP_*_20*"):
            for d in glob.glob(str(_Path(root)/pat)):
                rid=_Path(d).name
                try:
                    ts=_v3_parse_ts_from_rid(rid) or _Path(d).stat().st_mtime
                except Exception:
                    ts=_v3_parse_ts_from_rid(rid) or 0
                items.append({"rid": rid, "ts": float(ts or 0)})
    items.sort(key=lambda x: float(x.get("ts") or 0), reverse=True)
    out=[]
    for it in items[int(offset):int(offset)+int(limit)]:
        rid=it.get("rid",""); ts=float(it.get("ts") or 0)
        label=datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S") if ts>0 else rid
        out.append({"rid": rid, "label": label, "ts": ts})
    return out

def _v3_resolve_run_file(rid: str, rel: str):
    rid=_v3_norm_rid(rid)
    rel=(rel or "").lstrip("/").strip()
    if not rid or not rel: return None
    for root in _v3_guess_roots():
        base=_Path(root)/rid
        if base.exists() and base.is_dir():
            pth=base/rel
            if pth.exists(): return str(pth)
    return None

def _v3_pick_first_existing(rid: str, rel_paths):
    for rel in rel_paths:
        pth=_v3_resolve_run_file(rid, rel)
        if pth: return pth
    return None

def _v3_kind_map(kind: str):
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
    limit=max(1,min(limit,200)); offset=max(0,offset)
    runs=_v3_list_runs_raw(limit=200, offset=0)
    latest=_v3_rid_latest()
    if latest:
        runs=[r for r in runs if r.get("rid")!=latest]
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
    if not pth: return _v3_safe_err("gate summary not found", 404, rid=rid)
    try:
        j=json.loads(_Path(pth).read_text(encoding="utf-8", errors="replace"))
    except Exception as e:
        return _v3_safe_err("gate summary unreadable", 500, rid=rid, detail=str(e))
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
    limit=max(1,min(limit,500)); offset=max(0,offset)
    pth=_v3_pick_first_existing(rid, ["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"])
    if not pth: return _v3_safe_err("findings not found", 404, rid=rid)
    if fmt in ("raw","file"):
        return send_file(pth, as_attachment=False, mimetype="application/json", download_name="findings.json")
    try:
        data=json.loads(_Path(pth).read_text(encoding="utf-8", errors="replace"))
    except Exception as e:
        return _v3_safe_err("findings unreadable", 500, rid=rid, detail=str(e))
    items=data.get("findings") if isinstance(data, dict) else data
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
            it["file"]=_Path(f).name
    return jsonify({"ok": True, "rid": rid, "total": total, "limit": limit, "offset": offset, "items": page, "ts": _v3_now_iso()})

@app.get("/api/vsp/artifact_v3")
def api_vsp_artifact_v3():
    rid=_v3_norm_rid(request.args.get("rid")) or _v3_rid_latest()
    kind=(request.args.get("kind") or "").lower().strip()
    m=_v3_kind_map(kind)
    if not m: return _v3_safe_err("unknown kind", 400, rid=rid, kind=kind)
    pth=_v3_pick_first_existing(rid, m["candidates"])
    if not pth: return _v3_safe_err("artifact not found", 404, rid=rid, kind=kind)
    dn=m.get("download") or kind
    mt=m.get("mimetype") or (mimetypes.guess_type(dn)[0] or "application/octet-stream")
    as_att=(request.args.get("download")=="1")
    return send_file(pth, as_attachment=as_att, mimetype=mt, download_name=dn)

### === END CIO API v3 (AUTO) ===
''').strip("\n") + "\n"

if MARK in s and END in s:
    s2=re.sub(rf'{re.escape(MARK)}.*?{re.escape(END)}\n?', block, s, flags=re.S)
    if s2==s: raise SystemExit("markers found but replace failed")
    s=s2
    print("[OK] replaced CIO v3 block in", target.name)
elif MARK in s and END not in s:
    raise SystemExit("found MARK without END: file half-injected; restore backup then rerun")
else:
    # insert after "app =" if exists, else append
    m=re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)
    if m:
        # insert after app creation line (next newline)
        nl=s.find("\n", m.end())
        s = s[:nl+1] + "\n" + block + "\n" + s[nl+1:]
        print("[OK] inserted CIO v3 block after app=Flask(...)")
    else:
        s = s.rstrip() + "\n\n" + block
        print("[OK] appended CIO v3 block at EOF (no app=Flask marker)")

target.write_text(s, encoding="utf-8")

# compile only if it's a .py file (it is)
py_compile.compile(str(target), doraise=True)
print("[OK] py_compile ok", target.name)
PY "$TARGET"

echo "== [4] Restart service =="
sudo systemctl restart "$SVC" || {
  echo "[ERR] restart failed. Showing status + journal tail..."
  systemctl status "$SVC" --no-pager -l | tail -n 120 || true
  journalctl -xeu "$SVC" --no-pager | tail -n 160 || true
  exit 3
}
echo "[OK] restarted $SVC"

echo "== [5] Smoke v3 endpoints =="
curl -fsS "$BASE/api/vsp/rid_latest_v3" | head -c 240; echo
curl -fsS "$BASE/api/vsp/runs_v3?limit=3&offset=0" | head -c 240; echo
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_v3" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] latest RID=$RID"
curl -fsS "$BASE/api/vsp/run_gate_v3?rid=$RID" | head -c 240; echo
curl -fsS "$BASE/api/vsp/findings_v3?rid=$RID&limit=1&offset=0" | head -c 240; echo
echo "[DONE] backend v3 is live."
