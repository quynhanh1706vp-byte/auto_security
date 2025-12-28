#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl; need head

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_cio_v3_${TS}"
echo "[BACKUP] ${APP}.bak_cio_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# ---- inject only once
MARK = "### === CIO API v3 (AUTO) ==="
if MARK in s:
    print("[OK] CIO v3 already present, skip backend inject")
else:
    # Heuristic: inject near end of file (before if __name__ == '__main__' or at EOF)
    inject = textwrap.dedent(r'''
    {MARK}
    # NOTE: v3 endpoints are "CIO-clean": FE must not know internal file paths.
    # Debug is OFF by default; enable via ?debug=1 or localStorage VSP_DEBUG=1 (FE side).

    import os, json, time, mimetypes, glob
    from datetime import datetime
    from pathlib import Path
    from flask import request, jsonify, send_file, Response

    def _v3_is_debug():
        try:
            if request.args.get("debug") == "1":
                return True
        except Exception:
            pass
        return False

    def _v3_norm_rid(x):
        return (x or "").strip()

    def _v3_now_iso():
        return datetime.utcnow().isoformat(timespec="seconds") + "Z"

    def _v3_safe_err(msg, code=400, **extra):
        j = {"ok": False, "error": msg}
        j.update(extra)
        return jsonify(j), code

    def _v3_guess_roots():
        # Prefer env override if present
        env = os.environ.get("VSP_RUN_ROOTS") or os.environ.get("VSP_OUT_ROOTS") or ""
        roots = [r.strip() for r in env.split(":") if r.strip()]
        # Common roots in this project
        roots += [
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
        ]
        # De-dup while preserving order
        seen=set(); out=[]
        for r in roots:
            if r not in seen and Path(r).exists():
                seen.add(r); out.append(r)
        return out

    def _v3_parse_ts_from_rid(rid: str):
        # Examples: VSP_CI_20251218_114312 ; RUN_20251125_123008 ; RUN_VSP_FULL_EXT_DEMO_20251201_160000
        m = re.search(r'(20\d{2})(\d{2})(\d{2})[_-]?(\d{2})(\d{2})(\d{2})', rid or "")
        if not m:
            return None
        try:
            dt = datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                          int(m.group(4)), int(m.group(5)), int(m.group(6)))
            return dt.timestamp()
        except Exception:
            return None

    def _v3_try_call(fn_name, *a, **kw):
        # Call an existing function if present in module globals
        fn = globals().get(fn_name)
        if callable(fn):
            return fn(*a, **kw)
        return None

    def _v3_rid_latest():
        # Prefer existing rid_latest endpoint logic if present as function
        # Common patterns in your codebase: rid_latest(), api_rid_latest(), get_rid_latest()
        for name in ("rid_latest", "api_rid_latest", "get_rid_latest", "rid_latest_v1"):
            v = _v3_try_call(name)
            if v:
                # If it's a Flask response tuple/json, try extracting
                try:
                    if isinstance(v, dict) and v.get("rid"):
                        return v.get("rid")
                except Exception:
                    pass
        # Fallback: ask legacy endpoint via local call? Avoid HTTP recursion; do minimal scan.
        roots = _v3_guess_roots()
        candidates=[]
        for root in roots:
            # common rid folder patterns
            for pat in ("VSP_CI_20*", "RUN_20*", "RUN_VSP_*_20*"):
                for d in glob.glob(str(Path(root) / pat)):
                    bn = Path(d).name
                    ts = _v3_parse_ts_from_rid(bn) or Path(d).stat().st_mtime
                    candidates.append((ts, bn))
        candidates.sort(reverse=True)
        return candidates[0][1] if candidates else ""

    def _v3_list_runs_raw(limit=50, offset=0):
        # Prefer existing /api/vsp/runs backing function if exists
        # Common patterns: list_runs(), get_runs(), api_runs()
        for name in ("list_runs", "get_runs", "api_runs", "runs_v1"):
            v = _v3_try_call(name, limit=limit, offset=offset)
            if isinstance(v, dict) and isinstance(v.get("runs"), list):
                return v["runs"]
        # Fallback scan roots
        roots=_v3_guess_roots()
        items=[]
        for root in roots:
            for pat in ("VSP_CI_20*", "RUN_20*", "RUN_VSP_*_20*"):
                for d in glob.glob(str(Path(root) / pat)):
                    rid = Path(d).name
                    ts = _v3_parse_ts_from_rid(rid) or Path(d).stat().st_mtime
                    items.append({"rid": rid, "ts": ts, "root": root})
        # sort newest first
        items.sort(key=lambda x: float(x.get("ts") or 0), reverse=True)
        sliced = items[int(offset):int(offset)+int(limit)]
        # normalize: provide label for UI
        out=[]
        for it in sliced:
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
        # If legacy resolver exists, use it (do not leak to FE)
        for name in ("_resolve_run_file", "resolve_run_file", "_rid_path", "rid_path"):
            fn = globals().get(name)
            if callable(fn):
                try:
                    pth = fn(rid, rel)
                    if pth and Path(pth).exists():
                        return str(pth)
                except Exception:
                    pass
        # Otherwise: scan roots for rid folder and check candidate paths
        for root in _v3_guess_roots():
            base = Path(root) / rid
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
        # Do NOT expose internal names to FE; map "kind" -> internal candidates
        return {
            "gate": {
                "candidates": ["run_gate_summary.json", "reports/run_gate_summary.json", "report/run_gate_summary.json"],
                "download": "run_gate_summary.json",
                "mimetype": "application/json",
            },
            "findings": {
                "candidates": ["findings_unified.json", "reports/findings_unified.json", "report/findings_unified.json"],
                "download": "findings.json",
                "mimetype": "application/json",
            },
            "csv": {
                "candidates": ["reports/findings_unified.csv", "report/findings_unified.csv", "findings_unified.csv"],
                "download": "findings.csv",
                "mimetype": "text/csv",
            },
            "sarif": {
                "candidates": ["reports/findings_unified.sarif", "report/findings_unified.sarif", "findings_unified.sarif"],
                "download": "findings.sarif",
                "mimetype": "application/sarif+json",
            },
            "html": {
                "candidates": ["reports/index.html", "report/index.html", "reports/checkmarx_like.html", "report/checkmarx_like.html"],
                "download": "report.html",
                "mimetype": "text/html",
            },
            "pdf": {
                "candidates": ["reports/report.pdf", "report/report.pdf", "reports/vsp_report.pdf", "report/vsp_report.pdf"],
                "download": "report.pdf",
                "mimetype": "application/pdf",
            },
            "zip": {
                "candidates": ["reports/report.zip", "report/report.zip", "reports/artifacts.zip", "report/artifacts.zip"],
                "download": "artifacts.zip",
                "mimetype": "application/zip",
            },
            "tgz": {
                "candidates": ["reports/report.tgz", "report/report.tgz", "reports/artifacts.tgz", "report/artifacts.tgz"],
                "download": "artifacts.tgz",
                "mimetype": "application/gzip",
            },
        }.get(kind)

    # -------------------- v3 endpoints --------------------

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
        runs=_v3_list_runs_raw(limit=200, offset=0)  # get enough to enforce canonical latest
        latest=_v3_rid_latest()
        # Ensure canonical latest appears first if present
        if latest:
            runs=[r for r in runs if r.get("rid") != latest]
            # synth latest label/ts
            ts=_v3_parse_ts_from_rid(latest) or time.time()
            label=datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")
            runs.insert(0, {"rid": latest, "label": label, "ts": ts})
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
            j=json.loads(Path(pth).read_text(encoding="utf-8", errors="replace"))
        except Exception as e:
            return _v3_safe_err("gate summary unreadable", 500, rid=rid, detail=str(e))
        # scrub obvious plumbing keys if any
        for k in list(j.keys()):
            if isinstance(k,str) and ("path" in k.lower() or "file" in k.lower()):
                # keep only if value is not an absolute path
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
            # CIO-clean filename, no internal path
            return send_file(pth, as_attachment=False, mimetype="application/json", download_name="findings.json")

        try:
            data=json.loads(Path(pth).read_text(encoding="utf-8", errors="replace"))
        except Exception as e:
            return _v3_safe_err("findings unreadable", 500, rid=rid, detail=str(e))

        # normalize to list
        items = data.get("findings") if isinstance(data, dict) else data
        if not isinstance(items, list):
            items=[]

        def ok_item(it):
            if not isinstance(it, dict):
                return False
            if sev and (it.get("severity","").upper()!=sev):
                return False
            if q:
                blob=(" ".join([
                    str(it.get("title","")),
                    str(it.get("tool","")),
                    str(it.get("file","")),
                    str(it.get("cwe","")),
                    str(it.get("rule_id","")),
                ])).lower()
                if q not in blob:
                    return False
            return True

        filtered=[it for it in items if ok_item(it)]
        total=len(filtered)
        page=filtered[offset:offset+limit]

        # scrub absolute paths if any (keep basename)
        for it in page:
            f=it.get("file")
            if isinstance(f,str) and f.startswith("/"):
                it["file"]=Path(f).name

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
        # CIO: always return a neutral filename
        download_name=m.get("download") or f"{kind}"
        mt=m.get("mimetype") or (mimetypes.guess_type(download_name)[0] or "application/octet-stream")
        as_att = (request.args.get("download") == "1")
        return send_file(pth, as_attachment=as_att, mimetype=mt, download_name=download_name)

    @app.get("/api/vsp/dashboard_v3")
    def api_vsp_dashboard_v3():
        rid=_v3_norm_rid(request.args.get("rid")) or _v3_rid_latest()
        # Build KPI from gate summary if possible
        gate_pth=_v3_pick_first_existing(rid, ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"])
        gate={}
        if gate_pth:
            try:
                gate=json.loads(Path(gate_pth).read_text(encoding="utf-8", errors="replace"))
            except Exception:
                gate={}
        # Minimal CIO contract
        kpi={
            "rid": rid,
            "latest_rid": _v3_rid_latest(),
            "severity_counts": gate.get("severity_counts") or gate.get("counts") or {},
            "degraded": gate.get("degraded") if isinstance(gate, dict) else None,
        }
        # Trend: last N runs, take severity_counts.total if available
        runs=_v3_list_runs_raw(limit=30, offset=0)
        points=[]
        for r in runs[:20]:
            rr=r.get("rid","")
            gp=_v3_pick_first_existing(rr, ["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"])
            if not gp:
                continue
            try:
                gj=json.loads(Path(gp).read_text(encoding="utf-8", errors="replace"))
            except Exception:
                continue
            sc=gj.get("severity_counts") or gj.get("counts") or {}
            total=sc.get("total") if isinstance(sc, dict) else None
            if total is None and isinstance(gj, dict):
                total=gj.get("total_findings") or gj.get("total")
            points.append({
                "rid": rr,
                "label": r.get("label") or rr,
                "total": int(total or 0),
                "ts": r.get("ts"),
            })
        # Top findings (light): first 10 from findings, sorted by severity rank if present
        findings=[]
        fp=_v3_pick_first_existing(rid, ["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"])
        if fp:
            try:
                data=json.loads(Path(fp).read_text(encoding="utf-8", errors="replace"))
                items = data.get("findings") if isinstance(data, dict) else data
                if isinstance(items, list):
                    rank={"CRITICAL":5,"HIGH":4,"MEDIUM":3,"LOW":2,"INFO":1,"TRACE":0}
                    def key(it):
                        if not isinstance(it, dict): return -1
                        return rank.get(str(it.get("severity","")).upper(), -1)
                    items2=[it for it in items if isinstance(it, dict)]
                    items2.sort(key=key, reverse=True)
                    for it in items2[:10]:
                        f=it.get("file")
                        if isinstance(f,str) and f.startswith("/"):
                            it["file"]=Path(f).name
                        findings.append(it)
            except Exception:
                findings=[]
        return jsonify({
            "ok": True,
            "rid": rid,
            "latest_rid": _v3_rid_latest(),
            "kpi": kpi,
            "trend": points,
            "top_findings": findings,
            "ts": _v3_now_iso(),
        })

    '''.format(MARK=MARK))

    # Insert before main guard if present, else append
    m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
    if m:
        s = s[:m.start()] + inject + "\n\n" + s[m.start():]
    else:
        s = s.rstrip() + "\n\n" + inject + "\n"

    p.write_text(s, encoding="utf-8")
    print("[OK] injected CIO v3 backend block")

# Sanity compile
py_compile.compile("vsp_demo_app.py", doraise=True)
print("[OK] py_compile ok")
PY

echo "== [FE] Patch JS: move to v3 endpoints, remove run_file_allow leakage =="

# 1) Replace legacy endpoints in JS (best-effort)
# - run_file_allow -> artifact_v3/findings_v3/gate_v3
# - runs?limit=1 -> rid_latest_v3 (canonical latest)
# - top_findings/trend/run_gate_summary legacy -> dashboard_v3
python3 - <<'PY'
from pathlib import Path
import re, json

root = Path("static/js")
if not root.exists():
    print("[WARN] static/js not found, skipping FE patch")
    raise SystemExit(0)

targets = list(root.glob("*.js"))
changed = 0

def patch_text(t: str) -> str:
    # kill direct plumbing mentions
    t2 = t

    # replace runs?limit=1 polling for latest rid
    t2 = re.sub(r'(/api/vsp/runs\?[^"\']*limit=1[^"\']*)', '/api/vsp/rid_latest_v3', t2)

    # replace rid_latest old with v3 alias (keeps same semantics but clearer)
    t2 = t2.replace("/api/vsp/rid_latest", "/api/vsp/rid_latest_v3")

    # replace legacy top_findings/trend with dashboard_v3
    for ep in ["/api/vsp/top_findings_v1", "/api/vsp/trend_v1", "/api/vsp/run_gate_summary_v1", "/api/vsp/rid_latest_gate_root_v2"]:
        t2 = t2.replace(ep, "/api/vsp/dashboard_v3")

    # replace run_file_allow usage:
    # - if code references findings_unified.json -> findings_v3?format=raw
    t2 = t2.replace("/api/vsp/run_file_allow", "/api/vsp/artifact_v3")

    # scrub hardcoded internal filenames in strings (best-effort)
    for leak in ["findings_unified.json", "reports/findings_unified.json", "run_gate_summary.json", "reports/run_gate_summary.json"]:
        t2 = t2.replace(leak, "")

    # Convert common query param patterns:
    #   artifact_v3 expects kind=...
    # best-effort mapping of '?rid=...&path=...'
    t2 = re.sub(r'(\?/?.*?\brid=([^&"\']+)&path=)([^&"\']+)', r'?rid=\2&kind=findings', t2)

    return t2

for f in targets:
    s = f.read_text(encoding="utf-8", errors="replace")
    s2 = patch_text(s)
    if s2 != s:
        bak = f.with_suffix(f".js.bak_cio_v3_{Path().cwd().name}")
        # do not spam backups per file; create timestamped backup in-place naming
        # simpler: embed TS file side-by-side
        ts = "__CIOV3__"
        b = f.with_name(f.name + f".bak_cio_v3_{ts}")
        b.write_text(s, encoding="utf-8")
        f.write_text(s2, encoding="utf-8")
        changed += 1

print("[OK] FE patched files =", changed)
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
curl -fsS "$BASE/api/vsp/rid_latest_v3" | head -c 200; echo
curl -fsS "$BASE/api/vsp/runs_v3?limit=3&offset=0" | head -c 200; echo
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_v3" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] latest RID=$RID"
curl -fsS "$BASE/api/vsp/dashboard_v3?rid=$RID" | head -c 200; echo
curl -fsS "$BASE/api/vsp/run_gate_v3?rid=$RID" | head -c 200; echo
curl -fsS "$BASE/api/vsp/findings_v3?rid=$RID&limit=1&offset=0" | head -c 200; echo

echo
echo "[DONE] CIO v3 migration applied."
echo "Next: open /runs and do 60s click-through; artifacts should use /api/vsp/artifact_v3, data should use v3."
