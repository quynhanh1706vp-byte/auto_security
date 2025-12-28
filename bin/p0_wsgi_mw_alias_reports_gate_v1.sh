#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed; need grep

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_mw_alias_${TS}"
echo "[BACKUP] ${W}.bak_mw_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_WSGI_MW_ALIAS_REPORTS_GATE_V1"
if MARK in s:
    print("[OK] middleware marker already present")
    raise SystemExit(0)

mw = textwrap.dedent(r"""
# ===================== VSP_P0_WSGI_MW_ALIAS_REPORTS_GATE_V1 =====================
# Commercial P0: rewrite query string for /api/vsp/run_file_allow so UI can request
# reports/run_gate*.json even when artifacts are stored at root.
try:
  from urllib.parse import parse_qs, urlencode

  class _VSPAliasReportsGateMW:
    def __init__(self, app):
      self.app = app
    def __call__(self, environ, start_response):
      try:
        if (environ.get("PATH_INFO","") or "") == "/api/vsp/run_file_allow":
          qs = environ.get("QUERY_STRING","") or ""
          q = parse_qs(qs, keep_blank_values=True)
          path = (q.get("path") or [None])[0]
          if path in ("reports/run_gate_summary.json", "reports/run_gate.json"):
            q["path"] = [path.split("/", 1)[1]]  # drop "reports/"
            environ["QUERY_STRING"] = urlencode(q, doseq=True)
      except Exception:
        pass
      return self.app(environ, start_response)

  # wrap exported WSGI application if present
  if "application" in globals() and callable(globals().get("application")):
    application = _VSPAliasReportsGateMW(application)
except Exception:
  pass
# ===================== /VSP_P0_WSGI_MW_ALIAS_REPORTS_GATE_V1 =====================
""").strip("\n") + "\n"

# Insert near the end but before export markers if any (safer for order)
m = re.search(r"(?m)^#\s*=+\s*/VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C\s*=+\s*$", s)
if m:
    s2 = s[:m.start()] + mw + s[m.start():]
else:
    s2 = s + ("\n" if not s.endswith("\n") else "") + mw

p.write_text(s2, encoding="utf-8")
print("[OK] injected WSGI middleware:", MARK)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.7
echo "[OK] restarted (or attempted)"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_RUN_20251219_092640}"

echo "== reports gate summary (expect 200 now) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | sed -n '1,15p'
echo
echo "== reports gate (expect 200 now) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate.json" | sed -n '1,15p'
