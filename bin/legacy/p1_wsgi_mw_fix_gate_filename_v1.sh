#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed; need grep

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_gatefn_${TS}"
echo "[BACKUP] ${W}.bak_gatefn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

old_mark = "VSP_P0_WSGI_MW_ALIAS_REPORTS_GATE_V1"
new_mark = "VSP_P1_WSGI_MW_GATE_FILENAME_V1"

if new_mark in s:
    print("[OK] marker already present")
    raise SystemExit(0)

# Replace existing V1 block (if present) with improved block (keeps alias + fixes filename)
pat = re.compile(
    r"#\s*=+\s*VSP_P0_WSGI_MW_ALIAS_REPORTS_GATE_V1\s*=+.*?#\s*=+\s*/VSP_P0_WSGI_MW_ALIAS_REPORTS_GATE_V1\s*=+\s*\n",
    re.DOTALL
)

mw = textwrap.dedent(r"""
# ===================== VSP_P1_WSGI_MW_GATE_FILENAME_V1 =====================
# P1 polish: keep P0 alias, but fix Content-Disposition filename to match requested path.
try:
  from urllib.parse import parse_qs, urlencode

  class _VSPAliasReportsGateMW:
    def __init__(self, app):
      self.app = app

    def __call__(self, environ, start_response):
      orig_path = None

      # wrap start_response to adjust filename when needed
      def _sr(status, headers, exc_info=None):
        try:
          op = environ.get("_VSP_ORIG_RUNFILE_PATH") or ""
          if op in ("run_gate.json", "reports/run_gate.json"):
            new_headers = []
            for (k, v) in headers:
              if k.lower() == "content-disposition" and "__run_gate_summary.json" in (v or ""):
                new_headers.append((k, (v or "").replace("__run_gate_summary.json", "__run_gate.json")))
              else:
                new_headers.append((k, v))
            headers = new_headers
        except Exception:
          pass
        return start_response(status, headers, exc_info)

      try:
        if (environ.get("PATH_INFO","") or "") == "/api/vsp/run_file_allow":
          qs = environ.get("QUERY_STRING","") or ""
          q = parse_qs(qs, keep_blank_values=True)
          path = (q.get("path") or [None])[0]
          if path:
            orig_path = path.replace("\\","/").lstrip("/")
            environ["_VSP_ORIG_RUNFILE_PATH"] = orig_path

          # P0 alias: reports/run_gate*.json -> root gate*.json
          if orig_path in ("reports/run_gate_summary.json", "reports/run_gate.json"):
            q["path"] = [orig_path.split("/", 1)[1]]
            environ["QUERY_STRING"] = urlencode(q, doseq=True)
      except Exception:
        pass

      return self.app(environ, _sr)

  if "application" in globals() and callable(globals().get("application")):
    application = _VSPAliasReportsGateMW(application)
except Exception:
  pass
# ===================== /VSP_P1_WSGI_MW_GATE_FILENAME_V1 =====================
""").strip("\n") + "\n"

if pat.search(s):
    s2 = pat.sub(mw, s, count=1)
    p.write_text(s2, encoding="utf-8")
    print("[OK] replaced old alias block with filename-fix block")
else:
    # if old block not found, append new block (still safe)
    p.write_text(s + ("\n" if not s.endswith("\n") else "") + mw, encoding="utf-8")
    print("[OK] appended filename-fix middleware block")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.7
echo "[OK] restarted (or attempted)"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_RUN_20251219_092640}"

echo "== verify run_gate.json header filename should be __run_gate.json =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate.json" | sed -n '1,12p'

echo "== verify reports/run_gate.json header filename should be __run_gate.json =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate.json" | sed -n '1,12p'
