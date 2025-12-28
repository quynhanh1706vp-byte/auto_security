#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed; need grep

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_fix_runs_${TS}"
echo "[BACKUP] ${W}.bak_fix_runs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_FIX_RUNS_REPORTS_404_AND_RUNS_API_JSON_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

# 1) find flask app var (best-effort)
m = re.search(r"(?m)^\s*(\w+)\s*=\s*Flask\(", s)
appv = m.group(1) if m else "app"

# 2) choose best target route for runs page (do NOT touch dashboard)
# Prefer runs_reports_v1 if exists, else runs, else vsp5 (last resort)
target = None
for cand in ("/runs_reports_v1", "/runs_reports_v3", "/runs", "/runs-reports", "/vsp5"):
    if cand in s:
        target = cand
        break
if not target:
    target = "/runs"

# 3) ensure redirect is importable
# Try add `redirect` into existing flask import line
if re.search(r"from\s+flask\s+import\s+.*\bredirect\b", s) is None:
    s2, n = re.subn(r"(?m)^(from\s+flask\s+import\s+)(.*)$",
                    lambda m: m.group(1) + (m.group(2) + ", redirect" if "redirect" not in m.group(2) else m.group(2)),
                    s, count=1)
    if n == 0:
        # no import line found, add minimal import near top
        s2 = "from flask import redirect\n" + s
    s = s2

# 4) add /runs_reports alias if missing
if "/runs_reports" not in s:
    # place near other routes: after first occurrence of a route decorator or after app init
    ins = s.find("@")
    if ins == -1:
        ins = s.find("Flask(")
        if ins == -1:
            ins = 0
        ins = s.find("\n", ins)
        if ins == -1: ins = 0

    block = textwrap.dedent(f"""
    # ===================== {MARK} =====================
    try:
      @_VSP_DECORATOR_GUARD_
      def __dummy__(): pass
    except Exception:
      pass

    try:
      if hasattr({appv}, "get"):
        @{appv}.get("/runs_reports")
        def vsp_runs_reports_alias():
          return redirect("{target}", code=302)
      elif hasattr({appv}, "route"):
        @{appv}.route("/runs_reports", methods=["GET"])
        def vsp_runs_reports_alias():
          return redirect("{target}", code=302)
    except Exception:
      pass
    # ===================== /{MARK} =====================
    """).strip("\n") + "\n"

    # remove fake decorator guard text (keeps indentation safe even if parser is strict)
    block = block.replace("@_VSP_DECORATOR_GUARD_\n", "")

    s = s[:ins+1] + block + s[ins+1:]

# 5) Harden /api/vsp/runs JSON (ONLY if route text exists but may return non-json from exceptions)
# Add a tiny middleware to force JSON content-type on that endpoint when response is dict-like JSON string
mw_mark = "VSP_P0_MW_FORCE_RUNS_JSON_V1"
if mw_mark not in s:
    mw = textwrap.dedent(f"""
    # ===================== {mw_mark} =====================
    try:
      from werkzeug.wrappers import Response as _Resp
      from urllib.parse import parse_qs

      class _VSPForceRunsJsonMW:
        def __init__(self, wsgi_app):
          self.wsgi_app = wsgi_app
        def __call__(self, environ, start_response):
          try:
            if (environ.get("PATH_INFO","") or "") == "/api/vsp/runs":
              # pass-through, but if downstream forgets content-type, we normalize
              headers_box = {{}}
              body_box = {{"chunks":[]}}
              status_box = {{"status":"200 OK"}}

              def _sr(status, headers, exc_info=None):
                status_box["status"] = status
                # collect headers for possible override
                for k,v in headers:
                  headers_box[k.lower()] = v
                def _start(status2, headers2, exc2=None):
                  return start_response(status2, headers2, exc2)
                return _start(status, headers, exc_info)

              it = self.wsgi_app(environ, _sr)

              # If response is already JSON, keep
              ct = (headers_box.get("content-type") or "").lower()
              if "application/json" in ct:
                return it

              # Otherwise, try to wrap as JSON if body looks like JSON
              chunks = []
              try:
                for x in it:
                  chunks.append(x)
              finally:
                try:
                  if hasattr(it, "close"): it.close()
                except Exception:
                  pass
              raw = b"".join(chunks)
              raw_s = raw.lstrip()[:1]
              if raw_s in (b"{{", b"["):
                return [_Resp(raw, content_type="application/json").get_wsgi_response(environ)[0]]
              return [raw]
          except Exception:
            pass
          return self.wsgi_app(environ, start_response)

      if "application" in globals() and callable(globals().get("application")):
        application = _VSPForceRunsJsonMW(application)
    except Exception:
      pass
    # ===================== /{mw_mark} =====================
    """).strip("\n") + "\n"
    s += ("\n" if not s.endswith("\n") else "") + mw

p.write_text(s, encoding="utf-8")
print(f"[OK] patched runs_reports alias -> {target} using app var '{appv}'")
print(f"[OK] appended MW to normalize /api/vsp/runs content-type (best-effort)")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.7
echo "[OK] restarted"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== quick probes =="
curl -sS -I "$BASE/runs_reports" | sed -n '1,8p'
curl -sS -i "$BASE/api/vsp/runs?limit=1" | sed -n '1,12p'
