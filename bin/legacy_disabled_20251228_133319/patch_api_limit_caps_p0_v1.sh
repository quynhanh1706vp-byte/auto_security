#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

cp -f "$PYF" "$PYF.bak_caplimit_${TS}"
echo "[BACKUP] $PYF.bak_caplimit_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_API_LIMIT_CAPS_P0_V1" in s:
    print("[OK] caps already present")
else:
    s += r'''

# ================================
# VSP_API_LIMIT_CAPS_P0_V1
# - prevent OOM by capping heavy list endpoints
# ================================
def __vsp__wrap_limit_redirect(app, rule_path, cap):
  try:
    from flask import request, redirect
    from urllib.parse import urlencode
  except Exception:
    return
  try:
    ep = None
    for rule in app.url_map.iter_rules():
      if getattr(rule, "rule", "") == rule_path:
        ep = rule.endpoint
        break
    if not ep:
      return
    orig = app.view_functions.get(ep)
    if not callable(orig):
      return

    def _wrapped(*a, **kw):
      try:
        lim = request.args.get("limit", "")
        if lim:
          try:
            n = int(lim)
          except Exception:
            n = cap
          if n > cap:
            q = request.args.to_dict(flat=True)
            q["limit"] = str(cap)
            url = request.path + "?" + urlencode(q)
            return redirect(url, code=302)
      except Exception:
        pass
      return orig(*a, **kw)

    app.view_functions[ep] = _wrapped
  except Exception:
    pass

try:
  # cap datasource to 200, runs list to 50 (đủ dùng UI)
  __vsp__wrap_limit_redirect(app, "/api/vsp/datasource_v2", 200)
  __vsp__wrap_limit_redirect(app, "/api/vsp/runs_index_v3", 50)
except Exception:
  pass
'''
    p.write_text(s, encoding="utf-8")
    print("[OK] appended caps patch")
PY

python3 -m py_compile "$PYF" && echo "[OK] py_compile OK: $PYF"

echo "== restart low-mem =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/ui_restart_8910_lowmem_p0_v1.sh

echo "== verify caps (should 302 if limit too big) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/datasource_v2?limit=500" | head -n 12 || true
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs_index_v3?limit=200" | head -n 12 || true
