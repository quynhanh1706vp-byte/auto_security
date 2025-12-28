#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runfile_safe_${TS}"
echo "[BACKUP] ${F}.bak_runfile_safe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_RUN_FILE_SAFE_ENDPOINT_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
else:
    # Append new code at end (safe, minimal coupling)
    inject = r'''

# =========================
# VSP_RUN_FILE_SAFE_ENDPOINT_P0_V1
# - Serve per-run report/artifacts via whitelist (no absolute FS path leak)
# - Normalize "report/" vs "reports/" vs root file locations
# - Post-process /api/vsp/runs: replace any abs html_path with safe URL
# =========================
from pathlib import Path as _Path
from urllib.parse import quote as _quote
import os as _os
import json as _json
import mimetypes as _mimetypes
import re as _re

try:
    from flask import request as _request, abort as _abort, send_file as _send_file, Response as _Response
except Exception:
    _request = None  # type: ignore

_VSP_RUNFILE_ALLOWED = {
    # virtual_name: candidate real paths under RUN_DIR (first existing wins)
    "reports/index.html": [
        "reports/index.html",
        "report/index.html",
        "reports/report.html",
        "report/report.html",
        "report.html",
    ],
    "reports/findings_unified.json": [
        "reports/findings_unified.json",
        "report/findings_unified.json",
        "findings_unified.json",
        "reports/unified/findings_unified.json",
        "unified/findings_unified.json",
    ],
    "reports/findings_unified.csv": [
        "reports/findings_unified.csv",
        "report/findings_unified.csv",
        "findings_unified.csv",
        "reports/unified/findings_unified.csv",
        "unified/findings_unified.csv",
    ],
    "reports/findings_unified.sarif": [
        "reports/findings_unified.sarif",
        "report/findings_unified.sarif",
        "findings_unified.sarif",
        "reports/unified/findings_unified.sarif",
        "unified/findings_unified.sarif",
    ],
    "reports/run_gate_summary.json": [
        "reports/run_gate_summary.json",
        "report/run_gate_summary.json",
        "run_gate_summary.json",
        "reports/unified/run_gate_summary.json",
        "unified/run_gate_summary.json",
    ],
}

def _vsp__runs_roots():
    roots = []
    env = _os.environ.get("VSP_RUNS_ROOT", "").strip()
    if env:
        roots.append(_Path(env))
    # sensible defaults for this repo
    roots += [
        _Path("/home/test/Data/SECURITY_BUNDLE/out"),
        _Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        _Path("/home/test/Data/SECURITY-10-10-v4/out_ci"),
    ]
    # de-dup, keep existing dirs
    out = []
    seen = set()
    for r in roots:
        rp = str(r)
        if rp in seen:
            continue
        seen.add(rp)
        if r.exists():
            out.append(r)
    return out

def _vsp__is_safe_rid(rid: str) -> bool:
    return bool(rid) and bool(_re.fullmatch(r"[A-Za-z0-9_.:-]{6,128}", rid))

def _vsp__find_run_dir(rid: str):
    # direct hit
    for root in _vsp__runs_roots():
        cand = root / rid
        if cand.is_dir():
            return cand
        cand2 = root / "out" / rid
        if cand2.is_dir():
            return cand2
    # shallow scan (bounded)
    for root in _vsp__runs_roots():
        try:
            for cand in root.glob(f"*{rid}*"):
                if cand.is_dir() and cand.name == rid:
                    return cand
        except Exception:
            pass
    return None

def _vsp__pick_file(run_dir: _Path, virtual_name: str):
    cands = _VSP_RUNFILE_ALLOWED.get(virtual_name)
    if not cands:
        return None
    for rel in cands:
        fp = (run_dir / rel).resolve()
        try:
            # must stay under run_dir
            run_dir_res = run_dir.resolve()
            if not str(fp).startswith(str(run_dir_res) + _os.sep) and fp != run_dir_res:
                continue
            if fp.is_file():
                return fp
        except Exception:
            continue
    return None

def _vsp__safe_url(rid: str, virtual_name: str) -> str:
    return f"/api/vsp/run_file?rid={_quote(rid)}&name={_quote(virtual_name)}"

# ---- Endpoint: serve whitelisted per-run file
try:
    _app_obj = app  # noqa: F821
except Exception:
    _app_obj = None

if _app_obj is not None and getattr(_app_obj, "route", None) is not None:
    @_app_obj.get("/api/vsp/run_file")
    def _api_vsp_run_file():
        rid = (_request.args.get("rid", "") if _request else "").strip()
        name = (_request.args.get("name", "") if _request else "").strip()
        if not _vsp__is_safe_rid(rid):
            return _Response("bad rid", status=400, mimetype="text/plain")
        if name not in _VSP_RUNFILE_ALLOWED:
            return _Response("not allowed", status=404, mimetype="text/plain")

        run_dir = _vsp__find_run_dir(rid)
        if not run_dir:
            return _Response("run not found", status=404, mimetype="text/plain")

        fp = _vsp__pick_file(run_dir, name)
        if not fp:
            return _Response("file not found", status=404, mimetype="text/plain")

        ctype, _enc = _mimetypes.guess_type(str(fp))
        ctype = ctype or ("text/html" if str(fp).endswith(".html") else "application/octet-stream")
        # inline for html/json, attachment for others
        as_attachment = not (str(fp).endswith(".html") or str(fp).endswith(".json"))
        return _send_file(fp, mimetype=ctype, as_attachment=as_attachment, download_name=fp.name)

    # learned-safe postprocess: rewrite /api/vsp/runs JSON to avoid absolute paths + add safe urls
    @_app_obj.after_request
    def _vsp__after_request_safe_runs(resp):
        try:
            if not _request or _request.path != "/api/vsp/runs":
                return resp
            if "application/json" not in (resp.headers.get("Content-Type", "") or ""):
                return resp
            data = resp.get_json(silent=True)
            if not isinstance(data, dict):
                return resp
            items = data.get("items") or []
            if not isinstance(items, list):
                return resp

            for it in items:
                if not isinstance(it, dict):
                    continue
                rid = (it.get("run_id") or it.get("rid") or "").strip()
                if not _vsp__is_safe_rid(rid):
                    continue
                has = it.get("has")
                if not isinstance(has, dict):
                    has = {}
                    it["has"] = has

                run_dir = _vsp__find_run_dir(rid)
                if not run_dir:
                    continue

                # normalize: if file exists under any legacy location, mark true + set safe URL
                def mark(vname: str, flag: str, keypath: str):
                    fp = _vsp__pick_file(run_dir, vname)
                    if fp:
                        has[flag] = True
                        has[keypath] = _vsp__safe_url(rid, vname)

                mark("reports/index.html", "html", "html_path")
                mark("reports/findings_unified.json", "json", "json_path")
                mark("reports/findings_unified.csv", "csv", "csv_path")
                mark("reports/findings_unified.sarif", "sarif", "sarif_path")
                mark("reports/run_gate_summary.json", "summary", "summary_path")

                # if legacy code already stuffed abs path into html_path, force rewrite to safe url
                hp = has.get("html_path")
                if isinstance(hp, str) and hp.startswith("/"):
                    # only rewrite if we can actually serve a report
                    if _vsp__pick_file(run_dir, "reports/index.html"):
                        has["html_path"] = _vsp__safe_url(rid, "reports/index.html")

            # re-encode response
            body = _json.dumps(data, ensure_ascii=False)
            resp.set_data(body)
            resp.headers["Content-Length"] = str(len(body.encode("utf-8")))
            return resp
        except Exception:
            return resp
except Exception:
    pass

# =========================
# END VSP_RUN_FILE_SAFE_ENDPOINT_P0_V1
# =========================
'''
    s2 = s.rstrip() + "\n" + inject
    p.write_text(s2, encoding="utf-8")
    print("[OK] injected:", MARK)

print("[OK] wrote:", str(p))
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "== restart 8910 =="
if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service | grep -q 'vsp-ui-8910.service'; then
  sudo systemctl restart vsp-ui-8910.service
  sudo systemctl --no-pager --full status vsp-ui-8910.service | sed -n '1,18p'
else
  echo "[INFO] systemd unit not found; try your restart script, e.g.:"
  echo "  bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_lowmem_v2.sh"
fi

echo "== smoke =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,12p'
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,15p'
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | python3 - <<'PY'
import sys, json
d=json.load(sys.stdin)
it=(d.get("items") or [{}])[0]
print("run_id=", it.get("run_id"))
print("has=", it.get("has"))
PY
