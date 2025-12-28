#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

BAK="${PYF}.bak_contractize_rid_findings_${TS}"
cp -f "$PYF" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK0="VSP_P0_CONTRACTIZE_RID_LATEST_AND_FINDINGS_V2"
if MARK0 in s:
    print("[SKIP] already patched:", MARK0)
else:
    block = textwrap.dedent(r'''
    # ===================== VSP_P0_CONTRACTIZE_RID_LATEST_AND_FINDINGS_V2 =====================
    # Wrap existing endpoints to keep UI stable (no route overwrite)
    try:
        import os, json, time, csv, hashlib
        from pathlib import Path

        _VSP_RID_CACHE = {"ts": 0.0, "rid": None, "why": None}

        def _safe_json(payload, status=200):
            try:
                from flask import Response
                return Response(json.dumps(payload, ensure_ascii=False), status=status, mimetype="application/json; charset=utf-8")
            except Exception:
                return payload

        def _find_endpoint(app, rule_path: str):
            try:
                for r in app.url_map.iter_rules():
                    if getattr(r, "rule", None) == rule_path:
                        return r.endpoint
            except Exception:
                pass
            return None

        def _run_dirs_candidates():
            # reuse your existing roots logic if present, else default known locations
            roots = []
            # common: SECURITY_BUNDLE out_ci mirror, plus SECURITY-* workspace
            roots += ["/home/test/Data/SECURITY_BUNDLE/out", "/home/test/Data/SECURITY_BUNDLE/out_ci"]
            roots += ["/home/test/Data/SECURITY_BUNDLE/ui/out", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]
            # scan SECURITY-* out_ci folders (best-effort)
            try:
                base = Path("/home/test/Data")
                for d in base.glob("SECURITY-*"):
                    roots.append(str(d / "out_ci"))
            except Exception:
                pass
            # de-dup + only existing
            out=[]
            seen=set()
            for r in roots:
                if r in seen: 
                    continue
                seen.add(r)
                if Path(r).exists():
                    out.append(r)
            return out

        def _list_rids(max_n=1200):
            rids=[]
            for root in _run_dirs_candidates():
                rp = Path(root)
                try:
                    for d in rp.glob("*"):
                        if not d.is_dir():
                            continue
                        name = d.name
                        # accept common rid shapes
                        if name.startswith(("RUN_", "VSP_", "VSP_CI_", "VSP_CI_RUN_", "VSP_CI")):
                            rids.append((name, str(d)))
                except Exception:
                    continue
            # newest first by mtime
            rids.sort(key=lambda t: Path(t[1]).stat().st_mtime if Path(t[1]).exists() else 0, reverse=True)
            return rids[:max_n]

        def _has_good_artifacts(run_dir: str):
            d = Path(run_dir)
            # must have gate summary (KPI)
            gate = d / "run_gate_summary.json"
            if not gate.exists() or gate.stat().st_size < 50:
                return (False, None)
            # must have some form of findings source
            f_json = d / "findings_unified.json"
            f_rpt_json = d / "reports" / "findings_unified.json"
            f_csv = d / "reports" / "findings_unified.csv"
            if f_json.exists() and f_json.stat().st_size > 200:
                return (True, "findings_unified.json")
            if f_rpt_json.exists() and f_rpt_json.stat().st_size > 200:
                return (True, "reports/findings_unified.json")
            if f_csv.exists() and f_csv.stat().st_size > 200:
                return (True, "reports/findings_unified.csv")
            return (False, None)

        def _pick_latest_rid_strict():
            cand = _list_rids()
            checked=0
            for rid, run_dir in cand:
                checked += 1
                ok, why = _has_good_artifacts(run_dir)
                if ok:
                    return {"ok": True, "rid": rid, "why": why, "checked": checked, "candidates": len(cand)}
            return {"ok": False, "rid": None, "why": None, "checked": checked, "candidates": len(cand)}

        def _csv2json_sample(csv_path: Path, rid: str, limit: int):
            # cache by (path, mtime, limit)
            mtime = int(csv_path.stat().st_mtime)
            key = f"{rid}|{csv_path}|{mtime}|{limit}"
            h = hashlib.sha1(key.encode("utf-8", errors="ignore")).hexdigest()[:16]
            cache_dir = Path("/tmp/vsp_findings_cache")
            cache_dir.mkdir(parents=True, exist_ok=True)
            cache_file = cache_dir / f"findings_{rid}_{h}.json"
            if cache_file.exists() and cache_file.stat().st_size > 200:
                try:
                    return json.loads(cache_file.read_text(encoding="utf-8", errors="replace"))
                except Exception:
                    pass

            findings=[]
            counts={}
            total_rows=0

            def norm_sev(x: str):
                if not x: return "INFO"
                x = str(x).strip().upper()
                # normalize to your 6 levels
                if x in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"):
                    return x
                # map common variants
                if x in ("ERROR","SEVERE"): return "HIGH"
                if x in ("WARN","WARNING"): return "MEDIUM"
                if x in ("DEBUG",): return "TRACE"
                return "INFO"

            # robust DictReader
            with csv_path.open("r", encoding="utf-8", errors="replace", newline="") as f:
                reader = csv.DictReader(f)
                cols = [c for c in (reader.fieldnames or []) if c]
                # best-effort column picks
                def pick(row, keys):
                    for k in keys:
                        if k in row and row.get(k) not in (None,""):
                            return row.get(k)
                    return ""
                for row in reader:
                    total_rows += 1
                    sev = norm_sev(pick(row, ["severity","severity_norm","sev","level","priority"]))
                    counts[sev] = counts.get(sev, 0) + 1
                    if len(findings) < limit:
                        tool = pick(row, ["tool","scanner","engine","source"])
                        title = pick(row, ["title","message","rule","check","name"])
                        loc = pick(row, ["location","path","file","file_path","target"])
                        line = pick(row, ["line","line_start","start_line"])
                        if line and loc and (":" not in loc):
                            loc = f"{loc}:{line}"
                        findings.append({
                            "severity": sev,
                            "tool": (tool or "").strip() or "UNKNOWN",
                            "title": (title or "").strip() or "(no title)",
                            "location": (loc or "").strip() or "(no location)",
                        })

            # ensure all 6 levels exist
            for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
                counts.setdefault(k, 0)

            payload = {
                "ok": True,
                "from": "reports/findings_unified.csv",
                "meta": {
                    "rid": rid,
                    "generated_from": str(csv_path),
                    "generated_ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "limit": limit,
                    "total_rows": total_rows,
                    "truncated": total_rows > limit,
                    "counts_by_severity": counts,
                },
                "findings": findings,
            }
            try:
                cache_file.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            except Exception:
                pass
            return payload

        # ---- wrap rid_latest ----
        _ep_rid = _find_endpoint(app, "/api/vsp/rid_latest")
        if _ep_rid and _ep_rid in app.view_functions:
            _orig = app.view_functions[_ep_rid]
            def _rid_latest_wrapped(*args, **kwargs):
                now = time.time()
                # TTL cache 20s
                if _VSP_RID_CACHE["rid"] and (now - _VSP_RID_CACHE["ts"] < 20.0):
                    return _safe_json({"ok": True, "rid": _VSP_RID_CACHE["rid"], "stale": False, "why": _VSP_RID_CACHE["why"], "cached": True})
                res = _pick_latest_rid_strict()
                if res.get("ok") and res.get("rid"):
                    _VSP_RID_CACHE.update({"ts": now, "rid": res["rid"], "why": res.get("why")})
                return _safe_json(res)
            app.view_functions[_ep_rid] = _rid_latest_wrapped

        # ---- wrap run_file_allow for findings_unified.json ----
        _ep_rfa = _find_endpoint(app, "/api/vsp/run_file_allow")
        if _ep_rfa and _ep_rfa in app.view_functions:
            _orig_rfa = app.view_functions[_ep_rfa]
            from flask import request
            def _rfa_wrapped(*args, **kwargs):
                # call original first
                resp = _orig_rfa(*args, **kwargs)
                try:
                    path = (request.args.get("path") or "").strip()
                    rid = (request.args.get("rid") or "").strip()
                    if path != "findings_unified.json":
                        return resp
                    # if already ok:true json, keep it
                    txt = None
                    try:
                        txt = resp.get_data(as_text=True)  # type: ignore
                    except Exception:
                        pass
                    if txt:
                        try:
                            j = json.loads(txt)
                            if isinstance(j, dict) and j.get("ok") is True and (j.get("findings") or j.get("meta")):
                                return resp
                        except Exception:
                            pass

                    # generate from reports CSV if possible
                    limit = 200
                    try:
                        limit = int(request.args.get("limit") or 200)
                    except Exception:
                        limit = 200
                    limit = max(25, min(limit, 500))  # commercial-safe cap

                    # derive run_dir like your system does: best-effort search by RID in known roots
                    run_dir = None
                    for r, d in _list_rids(max_n=2000):
                        if r == rid:
                            run_dir = d
                            break
                    if not run_dir:
                        return _safe_json({"ok": False, "err": "run_dir not found", "rid": rid, "path": path, "marker": "VSP_P0_CONTRACTIZE_RID_LATEST_AND_FINDINGS_V2"}, 200)

                    d = Path(run_dir)
                    csv_path = d / "reports" / "findings_unified.csv"
                    if csv_path.exists() and csv_path.stat().st_size > 200:
                        payload = _csv2json_sample(csv_path, rid, limit)
                        return _safe_json(payload, 200)

                    # last resort: if reports/findings_unified.json exists, sample it
                    jpath = d / "reports" / "findings_unified.json"
                    if jpath.exists() and jpath.stat().st_size > 200:
                        try:
                            j = json.loads(jpath.read_text(encoding="utf-8", errors="replace"))
                            # normalize minimal shape
                            findings = j.get("findings") if isinstance(j, dict) else None
                            if isinstance(findings, list):
                                findings = findings[:limit]
                            return _safe_json({"ok": True, "from":"reports/findings_unified.json", "meta":{"rid":rid,"limit":limit,"truncated": True}, "findings": findings or []}, 200)
                        except Exception:
                            pass

                    return _safe_json({"ok": False, "err": "missing findings sources", "rid": rid, "path": path, "marker": "VSP_P0_CONTRACTIZE_RID_LATEST_AND_FINDINGS_V2"}, 200)
                except Exception as e:
                    return _safe_json({"ok": False, "err": f"wrapped exception: {e}", "marker": "VSP_P0_CONTRACTIZE_RID_LATEST_AND_FINDINGS_V2"}, 200)

            app.view_functions[_ep_rfa] = _rfa_wrapped

    except Exception:
        pass
    # ===================== /VSP_P0_CONTRACTIZE_RID_LATEST_AND_FINDINGS_V2 =====================
    ''').strip("\n") + "\n"

    s = s + "\n" + block
    p.write_text(s, encoding="utf-8")
    print("[OK] appended", MARK0, "into", p)

py_compile.compile("vsp_demo_app.py", doraise=True)
print("[OK] py_compile:", "vsp_demo_app.py")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] patched + restarted (best-effort): $SVC"
echo "[NEXT] verify contracts with curl below"
echo "  BASE=${BASE}"
echo "  curl -fsS \"${BASE}/api/vsp/rid_latest\" | python3 -c 'import sys,json; print(json.load(sys.stdin))'"
echo "  RID=\$(curl -fsS \"${BASE}/api/vsp/rid_latest\" | python3 -c 'import sys,json; print(json.load(sys.stdin).get(\"rid\"))')"
echo "  curl -fsS \"${BASE}/api/vsp/run_file_allow?rid=\$RID&path=run_gate_summary.json\" | head"
echo "  curl -fsS \"${BASE}/api/vsp/run_file_allow?rid=\$RID&path=findings_unified.json&limit=200\" | head -c 260; echo"
