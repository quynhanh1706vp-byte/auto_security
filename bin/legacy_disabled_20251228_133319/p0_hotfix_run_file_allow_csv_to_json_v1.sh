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

BAK="${PYF}.bak_runfileallow_csv2json_${TS}"
cp -f "$PYF" "$BAK"
echo "[BACKUP] $BAK"

export MARK="VSP_P0_RUN_FILE_ALLOW_CSV2JSON_FINDINGS_V1"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, os

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK=os.environ["MARK"]

if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

block=textwrap.dedent(r"""
# ===================== {MARK} =====================
try:
    import json, re, time, csv
    from pathlib import Path
    from flask import request, jsonify, send_file, make_response, Response

    _app = globals().get("app") or globals().get("application")
    if _app is None:
        print("[{MARK}] WARN: cannot find app/application in globals()")
    else:
        def _c2j_is_rid(v: str) -> bool:
            if not v: return False
            v=str(v).strip()
            if len(v)<6 or len(v)>140: return False
            if any(c.isspace() for c in v): return False
            if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.:-]+$", v): return False
            if not any(ch.isdigit() for ch in v): return False
            return True

        def _c2j_safe_relpath(pp: str) -> str:
            pp=(pp or "").strip()
            if not pp: return ""
            if pp.startswith("/"): return ""
            if ".." in pp: return ""
            pp = pp.replace("\\", "/")
            while "//" in pp: pp = pp.replace("//","/")
            if pp.startswith("./"): pp = pp[2:]
            if not pp: return ""
            if any(seg.strip()=="" for seg in pp.split("/")): return ""
            return pp

        def _c2j_allowed_path(rel: str) -> bool:
            rel=(rel or "").lower().strip()
            if not rel: return False
            exts=(".json",".sarif",".csv",".html",".txt",".log",".zip",".tgz",".gz")
            if not rel.endswith(exts): return False
            deny=("id_rsa","known_hosts",".pem",".key","passwd","shadow","token","secret")
            if any(x in rel for x in deny): return False
            return True

        def _c2j_roots():
            roots=[
                Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                Path("/home/test/Data/SECURITY_BUNDLE/out"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
            ]
            base=Path("/home/test/Data")
            if base.is_dir():
                try:
                    for d in base.iterdir():
                        if d.is_dir() and d.name.startswith("SECURITY"):
                            roots.append(d/"out_ci")
                            roots.append(d/"out")
                except Exception:
                    pass
            return roots

        def _c2j_find_run_dir(rid: str):
            cand=[]
            for r in _c2j_roots():
                try:
                    d=r/rid
                    if d.is_dir():
                        cand.append((d.stat().st_mtime, d))
                except Exception:
                    pass
            cand.sort(reverse=True, key=lambda t:t[0])
            return cand[0][1] if cand else None

        def _c2j_cache_path():
            return Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/_rid_latest_cache.json")

        def _c2j_guess_mime(rel: str) -> str:
            rel=(rel or "").lower()
            if rel.endswith(".json") or rel.endswith(".sarif"): return "application/json"
            if rel.endswith(".csv"): return "text/csv; charset=utf-8"
            if rel.endswith(".html"): return "text/html; charset=utf-8"
            if rel.endswith(".txt") or rel.endswith(".log"): return "text/plain; charset=utf-8"
            return "application/octet-stream"

        def _c2j_fallbacks(rel: str):
            if rel == "findings_unified.json":
                return [
                    "reports/findings_unified.json",
                    "reports/findings_unified_full.json",
                    "reports/findings_unified.csv",
                ]
            if rel == "run_gate_summary.json":
                return ["reports/run_gate_summary.json"]
            return []

        def _c2j_norm_sev(v: str) -> str:
            v=(v or "").strip().upper()
            if v in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"): return v
            m={"INFORMATIONAL":"INFO","INFORMATION":"INFO","WARN":"LOW","WARNING":"LOW","ERROR":"HIGH"}
            return m.get(v, v or "INFO")

        def _c2j_csv_to_unified_json(csv_path: Path, rid: str, max_rows: int = 12000):
            # cache next to csv to avoid re-parse
            cache = csv_path.parent / "_ui_cache_findings_unified_from_csv.json"
            try:
                if cache.is_file() and cache.stat().st_mtime >= csv_path.stat().st_mtime and cache.stat().st_size > 10:
                    return cache.read_text(encoding="utf-8", errors="replace"), True
            except Exception:
                pass

            findings=[]
            counts={"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}

            with csv_path.open("r", encoding="utf-8", errors="replace", newline="") as f:
                reader=csv.DictReader(f)
                # normalize headers
                for i,row in enumerate(reader):
                    if i >= max_rows:
                        break
                    r = { (k or "").strip().lower(): (v or "") for k,v in row.items() }

                    sev = _c2j_norm_sev(r.get("severity") or r.get("sev") or r.get("level"))
                    counts[sev] = counts.get(sev,0)+1

                    tool = (r.get("tool") or r.get("scanner") or r.get("engine") or "").strip() or "unknown"
                    title = (r.get("title") or r.get("check_name") or r.get("rule") or r.get("message") or "").strip()
                    loc = (r.get("location") or r.get("path") or r.get("file") or "").strip()
                    line = (r.get("line") or r.get("start_line") or "").strip()
                    rule_id = (r.get("rule_id") or r.get("id") or r.get("check_id") or "").strip()
                    desc = (r.get("description") or r.get("details") or r.get("message") or "").strip()

                    if line and loc and (":" not in loc):
                        loc = f"{loc}:{line}"

                    findings.append({
                        "severity": sev,
                        "tool": tool,
                        "rule_id": rule_id,
                        "title": title,
                        "location": loc,
                        "description": desc,
                        "rid": rid,
                        "source": "csv"
                    })

            meta={
                "rid": rid,
                "generated_from": str(csv_path),
                "generated_ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "counts_by_severity": counts,
                "findings_count": len(findings),
                "marker": "{MARK}"
            }
            out = json.dumps({"meta": meta, "findings": findings}, ensure_ascii=False)

            try:
                cache.write_text(out, encoding="utf-8")
            except Exception:
                pass
            return out, False

        def vsp_run_file_allow_csv2json_findings_v1():
            try:
                rid=(request.args.get("rid","") or "").strip()
                rel=_c2j_safe_relpath(request.args.get("path","") or "")

                if not _c2j_is_rid(rid):
                    return jsonify({"ok": False, "err": "bad rid", "rid": rid, "path": rel, "marker": "{MARK}"}), 200
                if not _c2j_allowed_path(rel):
                    return jsonify({"ok": False, "err": "not allowed", "rid": rid, "path": rel, "marker": "{MARK}"}), 200

                run_dir=_c2j_find_run_dir(rid)

                # fallback: cached path from rid_latest
                if run_dir is None:
                    cp=_c2j_cache_path()
                    try:
                        if cp.is_file():
                            j=json.loads(cp.read_text(encoding="utf-8", errors="replace") or "{}")
                            if (j.get("rid") or "").strip()==rid:
                                pth=(j.get("path") or "").strip()
                                if pth and Path(pth).is_dir():
                                    run_dir=Path(pth)
                    except Exception:
                        pass

                if run_dir is None:
                    return jsonify({"ok": False, "err": "rid dir not found", "rid": rid, "path": rel, "marker": "{MARK}"}), 200

                tried=[rel]
                fpath=run_dir/rel

                # try fallbacks
                if (not fpath.is_file()) and rel in ("findings_unified.json","run_gate_summary.json"):
                    for alt in _c2j_fallbacks(rel):
                        alt=_c2j_safe_relpath(alt)
                        if not alt:
                            continue
                        tried.append(alt)
                        ap=run_dir/alt
                        if ap.is_file() and ap.stat().st_size > 0:
                            rel=alt
                            fpath=ap
                            break

                if not fpath.is_file() or fpath.stat().st_size <= 0:
                    return jsonify({"ok": False, "err": "missing file", "rid": rid, "path": tried[0], "tried": tried,
                                    "run_dir": str(run_dir), "marker": "{MARK}"}), 200

                # CSV -> JSON for dashboard contract
                if tried[0] == "findings_unified.json" and rel.endswith(".csv") and fpath.name.lower().endswith(".csv"):
                    body, from_cache = _c2j_csv_to_unified_json(fpath, rid)
                    resp = Response(body, mimetype="application/json")
                    resp.headers["Cache-Control"]="no-store"
                    resp.headers["X-VSP-RUNFILEALLOW"]="{MARK}"
                    resp.headers["X-VSP-CSV2JSON"]="1"
                    resp.headers["X-VSP-CSV2JSON-CACHED"]="1" if from_cache else "0"
                    return resp

                resp=make_response(send_file(str(fpath), mimetype=_c2j_guess_mime(rel), as_attachment=False))
                resp.headers["Cache-Control"]="no-store"
                resp.headers["X-VSP-RUNFILEALLOW"]="{MARK}"
                return resp
            except Exception as e:
                return jsonify({"ok": False, "err": "exception", "detail": str(e)[:180], "marker": "{MARK}"}), 200

        # Force-bind by url_map (override previous handler)
        eps=[]
        try:
            for rule in list(_app.url_map.iter_rules()):
                if getattr(rule, "rule", "") == "/api/vsp/run_file_allow" and ("GET" in (rule.methods or set())):
                    eps.append(rule.endpoint)
        except Exception as e:
            print("[{MARK}] WARN url_map scan failed:", repr(e))

        if eps:
            for ep in eps:
                _app.view_functions[ep] = vsp_run_file_allow_csv2json_findings_v1
            print("[{MARK}] OK rebound existing endpoints:", eps)
        else:
            _app.add_url_rule("/api/vsp/run_file_allow", "vsp_run_file_allow_csv2json_findings_v1",
                              vsp_run_file_allow_csv2json_findings_v1, methods=["GET"])
            print("[{MARK}] OK added new rule endpoint=vsp_run_file_allow_csv2json_findings_v1")

except Exception as _e:
    print("[{MARK}] FAILED:", repr(_e))
# ===================== /{MARK} =====================
""").replace("{MARK}", MARK).strip()+"\n"

m=re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m:
    s = s[:m.start()] + block + "\n" + s[m.start():]
else:
    s = s.rstrip() + "\n\n" + block

p.write_text(s, encoding="utf-8")
print("[OK] appended", MARK, "into", p)
PY

if ! python3 -m py_compile "$PYF" >/dev/null 2>&1; then
  echo "[ERR] py_compile failed => rollback to $BAK"
  cp -f "$BAK" "$PYF"
  python3 -m py_compile "$PYF" >/dev/null 2>&1 || true
  exit 3
fi
echo "[OK] py_compile: $PYF"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] run_file_allow now converts reports/findings_unified.csv -> findings_unified.json (cached)."
