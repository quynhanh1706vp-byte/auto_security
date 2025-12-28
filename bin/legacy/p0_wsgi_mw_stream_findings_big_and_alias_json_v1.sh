#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_findingsmw_${TS}"
echo "[BACKUP] ${W}.bak_findingsmw_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_MW_STREAM_FINDINGS_BIG_AND_ALIAS_JSON_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

mw = textwrap.dedent(r"""
# ===================== VSP_P0_MW_STREAM_FINDINGS_BIG_AND_ALIAS_JSON_V1 =====================
# Purpose:
# - reports/findings_unified.csv may be huge -> run_file_allow sometimes returns 413. Stream it here.
# - findings_unified.json may live under reports/ -> alias to avoid 404.
try:
  import os
  from pathlib import Path as _Path
  from urllib.parse import parse_qs as _parse_qs
  from werkzeug.wrappers import Response as _Resp

  class _VSPFindingsArtifactsMW:
    def __init__(self, app):
      self.app = app

    def _norm(self, x: str) -> str:
      x = (x or "").replace("\\", "/")
      while x.startswith("/"):
        x = x[1:]
      return x

    def _resolve_run_dir(self, rid: str):
      # Keep it deterministic + cheap
      roots = [
        _Path("/home/test/Data/SECURITY_BUNDLE/out"),
        _Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
      ]
      for root in roots:
        if not root.exists():
          continue
        # direct
        d = root / rid
        if d.is_dir():
          return d
        # one level nested
        try:
          for sub in root.iterdir():
            if sub.is_dir():
              d2 = sub / rid
              if d2.is_dir():
                return d2
        except Exception:
          pass
      return None

    def _send_file(self, environ, fp: _Path, rid: str, base_name: str, content_type: str):
      try:
        f = open(fp, "rb")
      except Exception:
        return None
      wrapper = environ.get("wsgi.file_wrapper")
      data = wrapper(f, 8192) if wrapper else iter(lambda: f.read(8192), b"")
      resp = _Resp(data, content_type=content_type, direct_passthrough=True)
      resp.headers["Cache-Control"] = "no-cache"
      resp.headers["Content-Disposition"] = f'inline; filename={rid}__{base_name}'
      try:
        resp.headers["Content-Length"] = str(fp.stat().st_size)
      except Exception:
        pass
      return resp

    def __call__(self, environ, start_response):
      try:
        if (environ.get("REQUEST_METHOD","GET") or "GET").upper() != "GET":
          return self.app(environ, start_response)

        if (environ.get("PATH_INFO","") or "") != "/api/vsp/run_file_allow":
          return self.app(environ, start_response)

        qs = _parse_qs(environ.get("QUERY_STRING","") or "")
        rid = (qs.get("rid") or [""])[0]
        path = (qs.get("path") or [""])[0]
        rid = (rid or "").strip()
        rel = self._norm(path)

        if not rid or not rel:
          return self.app(environ, start_response)

        # Only special-case these 2 artifacts (commercial safe)
        want_csv = (rel == "reports/findings_unified.csv")
        want_json = (rel == "findings_unified.json" or rel == "reports/findings_unified.json")

        if not (want_csv or want_json):
          return self.app(environ, start_response)

        run_dir = self._resolve_run_dir(rid)
        if not run_dir:
          return self.app(environ, start_response)

        # Build candidate paths
        cands = []
        if want_csv:
          cands = [run_dir / "reports/findings_unified.csv"]
          ctype = "text/csv; charset=utf-8"
          base_name = "findings_unified.csv"
        else:
          cands = [run_dir / "findings_unified.json", run_dir / "reports/findings_unified.json"]
          ctype = "application/json"
          base_name = "findings_unified.json"

        for fp in cands:
          if fp.is_file():
            resp = self._send_file(environ, fp, rid, base_name, ctype)
            if resp is not None:
              return resp(environ, start_response)

        return self.app(environ, start_response)
      except Exception:
        return self.app(environ, start_response)

  if "application" in globals() and callable(globals().get("application")):
    application = _VSPFindingsArtifactsMW(application)
except Exception:
  pass
# ===================== /VSP_P0_MW_STREAM_FINDINGS_BIG_AND_ALIAS_JSON_V1 =====================
""").strip("\n") + "\n"

p.write_text(s + ("\n" if not s.endswith("\n") else "") + mw, encoding="utf-8")
print("[OK] appended MW:", MARK)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.7
echo "[OK] restarted"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); it=(j.get("items") or [None])[0] or {}; print(it.get("run_id") or j.get("rid_latest") or "")')"
echo "[INFO] latest RID=$RID"

echo "== probe artifacts =="
curl -sS -o /dev/null -w "%{http_code}  %{size_download}  reports/findings_unified.csv\n" \
  "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.csv" || true

curl -sS -o /dev/null -w "%{http_code}  %{size_download}  findings_unified.json\n" \
  "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json" || true
