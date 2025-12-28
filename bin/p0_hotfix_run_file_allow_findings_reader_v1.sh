#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

BAK="${PYF}.bak_findings_reader_${TS}"
cp -f "$PYF" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RUN_FILE_ALLOW_FINDINGS_READER_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block=textwrap.dedent(r'''
    # ===================== VSP_P0_RUN_FILE_ALLOW_FINDINGS_READER_V1 =====================
    # Improve findings_unified.json serving: support root json + reports json(list/dict) + csv sample.
    try:
        import json, time, csv, hashlib
        from pathlib import Path
        from flask import request

        def _safe_json_v1(payload, status=200):
            from flask import Response
            return Response(json.dumps(payload, ensure_ascii=False), status=status, mimetype="application/json; charset=utf-8")

        def _find_endpoint_v1(app, rule_path: str):
            for r in app.url_map.iter_rules():
                if getattr(r, "rule", None) == rule_path:
                    return r.endpoint
            return None

        def _run_dirs_candidates_v1():
            roots=[]
            roots += ["/home/test/Data/SECURITY_BUNDLE/out", "/home/test/Data/SECURITY_BUNDLE/out_ci"]
            roots += ["/home/test/Data/SECURITY_BUNDLE/ui/out", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]
            try:
                base=Path("/home/test/Data")
                for d in base.glob("SECURITY-*"):
                    roots.append(str(d/"out_ci"))
            except Exception:
                pass
            out=[]; seen=set()
            for r in roots:
                if r in seen: 
                    continue
                seen.add(r)
                if Path(r).exists():
                    out.append(r)
            return out

        def _list_rids_v1(max_n=2500):
            rids=[]
            for root in _run_dirs_candidates_v1():
                rp=Path(root)
                try:
                    for d in rp.glob("*"):
                        if d.is_dir() and d.name.startswith(("RUN_","VSP_","VSP_CI","VSP_CI_")):
                            rids.append((d.name, str(d)))
                except Exception:
                    continue
            rids.sort(key=lambda t: Path(t[1]).stat().st_mtime if Path(t[1]).exists() else 0, reverse=True)
            return rids[:max_n]

        def _find_run_dir_by_rid_v1(rid: str):
            for r, d in _list_rids_v1():
                if r == rid:
                    return d
            return None

        def _csv2json_sample_v1(csv_path: Path, rid: str, limit: int):
            mtime=int(csv_path.stat().st_mtime)
            key=f"{rid}|{csv_path}|{mtime}|{limit}"
            h=hashlib.sha1(key.encode("utf-8", errors="ignore")).hexdigest()[:16]
            cache_dir=Path("/tmp/vsp_findings_cache"); cache_dir.mkdir(parents=True, exist_ok=True)
            cache_file=cache_dir/f"findings_{rid}_{h}.json"
            if cache_file.exists() and cache_file.stat().st_size>200:
                try: return json.loads(cache_file.read_text(encoding="utf-8", errors="replace"))
                except Exception: pass

            findings=[]; counts={}; total_rows=0
            def norm_sev(x):
                if not x: return "INFO"
                x=str(x).strip().upper()
                if x in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"): return x
                if x in ("ERROR","SEVERE"): return "HIGH"
                if x in ("WARN","WARNING"): return "MEDIUM"
                if x in ("DEBUG",): return "TRACE"
                return "INFO"

            with csv_path.open("r", encoding="utf-8", errors="replace", newline="") as f:
                reader=csv.DictReader(f)
                def pick(row, keys):
                    for k in keys:
                        if k in row and row.get(k) not in (None,""):
                            return row.get(k)
                    return ""
                for row in reader:
                    total_rows += 1
                    sev=norm_sev(pick(row, ["severity","severity_norm","sev","level","priority"]))
                    counts[sev]=counts.get(sev,0)+1
                    if len(findings) < limit:
                        tool=(pick(row, ["tool","scanner","engine","source"]) or "").strip() or "UNKNOWN"
                        title=(pick(row, ["title","message","rule","check","name"]) or "").strip() or "(no title)"
                        loc=(pick(row, ["location","path","file","file_path","target"]) or "").strip() or "(no location)"
                        line=(pick(row, ["line","line_start","start_line"]) or "").strip()
                        if line and loc and (":" not in loc):
                            loc=f"{loc}:{line}"
                        findings.append({"severity": sev, "tool": tool, "title": title, "location": loc})

            for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
                counts.setdefault(k,0)

            payload={
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
            try: cache_file.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            except Exception: pass
            return payload

        def _read_findings_json_anyshape_v1(jpath: Path, rid: str, limit: int):
            # supports: list[...] OR dict{findings:[...]} OR dict{data/items/results:[...]}
            raw = jpath.read_text(encoding="utf-8", errors="replace")
            j = json.loads(raw)
            findings=None
            if isinstance(j, list):
                findings = j
            elif isinstance(j, dict):
                for key in ("findings","data","items","results"):
                    v = j.get(key)
                    if isinstance(v, list):
                        findings = v
                        break
            if not isinstance(findings, list):
                findings=[]
            return {
                "ok": True,
                "from": str(jpath).split("/"+rid+"/",1)[-1] if ("/"+rid+"/") in str(jpath) else jpath.name,
                "meta": {"rid": rid, "limit": limit, "truncated": len(findings) > limit},
                "findings": findings[:limit],
            }

        _ep = _find_endpoint_v1(app, "/api/vsp/run_file_allow")
        if _ep and _ep in app.view_functions:
            _orig = app.view_functions[_ep]

            def _run_file_allow_wrapped_v1(*args, **kwargs):
                resp = _orig(*args, **kwargs)
                try:
                    path=(request.args.get("path") or "").strip()
                    if path != "findings_unified.json":
                        return resp

                    rid=(request.args.get("rid") or "").strip()
                    if not rid:
                        return _safe_json_v1({"ok": False, "err":"missing rid", "marker":"VSP_P0_RUN_FILE_ALLOW_FINDINGS_READER_V1"}, 200)

                    limit=200
                    try: limit=int(request.args.get("limit") or 200)
                    except Exception: limit=200
                    limit=max(25, min(limit, 500))

                    run_dir=_find_run_dir_by_rid_v1(rid)
                    if not run_dir:
                        return _safe_json_v1({"ok": False, "err":"run_dir not found", "rid":rid, "marker":"VSP_P0_RUN_FILE_ALLOW_FINDINGS_READER_V1"}, 200)

                    d=Path(run_dir)

                    # 1) prefer root findings_unified.json (most correct)
                    rootj=d/"findings_unified.json"
                    if rootj.exists() and rootj.stat().st_size>200:
                        try:
                            raw = rootj.read_text(encoding="utf-8", errors="replace")
                            j = json.loads(raw)
                            if isinstance(j, dict) and isinstance(j.get("findings"), list):
                                return _safe_json_v1({"ok": True, "from":"findings_unified.json", "meta": j.get("meta") or {"rid":rid,"limit":limit,"truncated": len(j["findings"])>limit}, "findings": j["findings"][:limit]}, 200)
                            if isinstance(j, list):
                                return _safe_json_v1({"ok": True, "from":"findings_unified.json", "meta":{"rid":rid,"limit":limit,"truncated": len(j)>limit}, "findings": j[:limit]}, 200)
                        except Exception:
                            pass

                    # 2) reports/findings_unified.json any-shape
                    rptj=d/"reports"/"findings_unified.json"
                    if rptj.exists() and rptj.stat().st_size>50:
                        try:
                            payload=_read_findings_json_anyshape_v1(rptj, rid, limit)
                            return _safe_json_v1(payload, 200)
                        except Exception:
                            pass

                    # 3) reports/findings_unified.csv -> sample
                    csvp=d/"reports"/"findings_unified.csv"
                    if csvp.exists() and csvp.stat().st_size>200:
                        payload=_csv2json_sample_v1(csvp, rid, limit)
                        return _safe_json_v1(payload, 200)

                    return _safe_json_v1({"ok": False, "err":"missing findings sources", "rid":rid, "marker":"VSP_P0_RUN_FILE_ALLOW_FINDINGS_READER_V1"}, 200)
                except Exception as e:
                    return _safe_json_v1({"ok": False, "err": f""{e}"", "marker":"VSP_P0_RUN_FILE_ALLOW_FINDINGS_READER_V1"}, 200)

            app.view_functions[_ep] = _run_file_allow_wrapped_v1

    except Exception:
        pass
    # ===================== /VSP_P0_RUN_FILE_ALLOW_FINDINGS_READER_V1 =====================
    ''').strip("\n") + "\n"

    s = s + "\n" + block
    p.write_text(s, encoding="utf-8")
    print("[OK] appended", MARK)

py_compile.compile("vsp_demo_app.py", doraise=True)
print("[OK] py_compile: vsp_demo_app.py")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] patched + restarted (best-effort): $SVC"
