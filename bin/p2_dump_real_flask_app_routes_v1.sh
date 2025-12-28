#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

python3 - <<'PY'
import wsgi_vsp_ui_gateway as m
from collections import deque

def is_real_flask(x):
    um = getattr(x, "url_map", None)
    vf = getattr(x, "view_functions", None)
    return um is not None and hasattr(um, "iter_rules") and isinstance(vf, dict)

def bfs_find_real(root):
    q=deque([root])
    seen=set()
    while q:
        x=q.popleft()
        if x is None: 
            continue
        if id(x) in seen:
            continue
        seen.add(id(x))
        if is_real_flask(x):
            return x
        # common wrapper attrs
        for k in ("app","application","wsgi_app","_app","inner","wrapped","target","_target"):
            y=getattr(x,k,None)
            if y is not None:
                q.append(y)
        # scan object __dict__ shallow
        d=getattr(x,"__dict__",{}) or {}
        for k,v in list(d.items())[:80]:
            if v is not None:
                q.append(v)
    return None

root = getattr(m, "application", None) or getattr(m, "app", None) or m
real = bfs_find_real(root)
print("REAL_FLASK_APP=", type(real))

if not real:
    raise SystemExit("cannot find real Flask app")

# dump endpoints we care about
want = {"/api/vsp/rid_latest", "/api/vsp/top_findings_v1", "/api/vsp/ui_health_v2", "/api/vsp/trend_v1"}
for r in real.url_map.iter_rules():
    if any(str(r.rule).startswith(p) for p in want):
        print("RULE:", r.rule, "endpoint=", r.endpoint, "methods=", sorted(list(r.methods or [])))
PY
