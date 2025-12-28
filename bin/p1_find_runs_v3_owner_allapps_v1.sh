#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
python3 - <<'PY'
import importlib.util
from flask import Flask

spec = importlib.util.spec_from_file_location("wsgi_mod", "wsgi_vsp_ui_gateway.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

apps = [(k,v) for k,v in m.__dict__.items() if isinstance(v, Flask)]
print("== Flask apps found ==", [k for k,_ in apps])
print("== likely gunicorn entrypoints ==")
for k in ("application","app","_app","_vsp_app","_vsp_inner","_orig_app","_orig_app_runs"):
    if k in m.__dict__:
        v=m.__dict__[k]
        print(f"  {k}: type={type(v)} repr={repr(v)[:120]}")

print("\n== scan /api/ui/runs_v3 across ALL apps ==")
found = 0
for name, app in apps:
    for rule in app.url_map.iter_rules():
        if rule.rule == "/api/ui/runs_v3":
            vf = app.view_functions.get(rule.endpoint)
            print(f"[APP={name}] RULE={rule} methods={sorted(rule.methods)} endpoint={rule.endpoint}")
            print(f"           VIEW_FUNC name={getattr(vf,'__name__',None)} module={getattr(vf,'__module__',None)} obj={vf}")
            found += 1
if not found:
    print("[WARN] No Flask url_map contained exact rule '/api/ui/runs_v3'. (It might be mounted via wrapper/wsgi routing.)")
PY
