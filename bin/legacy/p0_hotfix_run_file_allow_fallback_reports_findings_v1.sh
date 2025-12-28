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

BAK="${PYF}.bak_runfileallow_fallback_${TS}"
cp -f "$PYF" "$BAK"
echo "[BACKUP] $BAK"

export MARK="VSP_P0_RUN_FILE_ALLOW_FALLBACK_REPORTS_FINDINGS_V1"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, os

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK=os.environ["MARK"]

if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

block=textwrap.dedent("""
# ===================== {MARK} =====================
try:
    import json, re
    from pathlib import Path
    from flask import request, jsonify, send_file, make_response

    _app = globals().get("app") or globals().get("application")
    if _app is None:
        print("[{MARK}] WARN: cannot find app/application in globals()")
    else:
        def _rf_is_rid(v: str) -> bool:
            if not v: return False
            v=str(v).strip()
            if len(v)<6 or len(v)>140: return False
            if any(c.isspace() for c in v): return False
            if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.:-]+$", v): return False
            if not any(ch.isdigit() for ch in v): return False
            return True

        def _rf_safe_relpath(pp: str) -> str:
            pp=(pp or "").strip()
            if not pp: return ""
            if pp.startswith("/"): return ""      # forbid abs
            if ".." in pp: return ""             # forbid traversal
            pp = pp.replace("\\\\", "/")
            while "//" in pp: pp = pp.replace("//","/")
            if pp.startswith("./"): pp = pp[2:]
            if not pp: return ""
            if any(seg.strip()=="" for seg in pp.split("/")): return ""
            return pp

        def _rf_allowed_path(rel: str) -> bool:
            rel=(rel or "").lower().strip()
            if not rel: return False
            exts=(".json",".sarif",".csv",".html",".txt",".log",".zip",".tgz",".gz")
            if not rel.endswith(exts): return False
            deny=("id_rsa","known_hosts",".pem",".key","passwd","shadow","token","secret")
            if any(x in rel for x in deny): return False
            return True

        def _rf_roots():
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

        def _rf_find_run_dir(rid: str):
            cand=[]
            for r in _rf_roots():
                try:
                    d=r/rid
                    if d.is_dir():
                        cand.append((d.stat().st_mtime, d))
                except Exception:
                    pass
            cand.sort(reverse=True, key=lambda t:t[0])
            return cand[0][1] if cand else None

        def _rf_cache_path():
            return Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/_rid_latest_cache.json")

        def _rf_guess_mime(rel: str) -> str:
            rel=(rel or "").lower()
            if rel.endswith(".json") or rel.endswith(".sarif"): return "application/json"
            if rel.endswith(".csv"): return "text/csv; charset=utf-8"
            if rel.endswith(".html"): return "text/html; charset=utf-8"
            if rel.endswith(".txt") or rel.endswith(".log"): return "text/plain; charset=utf-8"
            return "application/octet-stream"

        def _rf_fallbacks(rel: str):
            # when dashboard requests root but artifacts are under reports/
            if rel == "findings_unified.json":
                return ["reports/findings_unified.json", "reports/findings_unified_full.json"]
            if rel == "run_gate_summary.json":
                return ["reports/run_gate_summary.json"]
            return []

        def vsp_run_file_allow_fallback_reports_findings_v1():
            try:
                rid=(request.args.get("rid","") or "").strip()
                rel=_rf_safe_relpath(request.args.get("path","") or "")

                if not _rf_is_rid(rid):
                    return jsonify({"ok": False, "err": "bad rid", "rid": rid, "path": rel, "marker": "{MARK}"}), 200
                if not _rf_allowed_path(rel):
                    return jsonify({"ok": False, "err": "not allowed", "rid": rid, "path": rel, "marker": "{MARK}"}), 200

                run_dir=_rf_find_run_dir(rid)

                # fallback: cached path from rid_latest
                if run_dir is None:
                    cp=_rf_cache_path()
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

                # try primary path, then fallbacks if missing
                tried=[rel]
                fpath=run_dir/rel
                if (not fpath.is_file()) and rel in ("findings_unified.json","run_gate_summary.json"):
                    for alt in _rf_fallbacks(rel):
                        alt=_rf_safe_relpath(alt)
                        if not alt: 
                            continue
                        tried.append(alt)
                        ap=run_dir/alt
                        if ap.is_file():
                            rel=alt
                            fpath=ap
                            break

                if not fpath.is_file():
                    return jsonify({"ok": False, "err": "missing file", "rid": rid, "path": tried[0], "tried": tried,
                                    "run_dir": str(run_dir), "marker": "{MARK}"}), 200

                resp=make_response(send_file(str(fpath), mimetype=_rf_guess_mime(rel), as_attachment=False))
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
                _app.view_functions[ep] = vsp_run_file_allow_fallback_reports_findings_v1
            print("[{MARK}] OK rebound existing endpoints:", eps)
        else:
            _app.add_url_rule("/api/vsp/run_file_allow", "vsp_run_file_allow_fallback_reports_findings_v1",
                              vsp_run_file_allow_fallback_reports_findings_v1, methods=["GET"])
            print("[{MARK}] OK added new rule endpoint=vsp_run_file_allow_fallback_reports_findings_v1")

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
echo "[DONE] run_file_allow now falls back to reports/ for findings_unified.json."
