#!/usr/bin/env bash
set -euo pipefail
export VSP_DISABLE_RUNAPI_FALLBACK=1
python3 - <<'PY'
import flask
import vsp_demo_app as mod

app = None
for k,v in vars(mod).items():
    if isinstance(v, flask.Flask):
        app = v
        break
print("[APP]", app)

rules = sorted(app.url_map.iter_rules(), key=lambda r: r.rule)
print("== ROUTES startswith /api/vsp/ ==")
n=0
for r in rules:
    if r.rule.startswith("/api/vsp/"):
        n += 1
        print(f"{n:03d} {sorted([m for m in r.methods if m not in ('HEAD','OPTIONS')])}  {r.rule}  -> {r.endpoint}")
print("TOTAL", n)
PY
