#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kics_summary_${TS}"
echo "[BACKUP] $F.bak_kics_summary_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG="# === VSP_STATUS_INJECT_KICS_SUMMARY_V1 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

inject = r'''
%s
def _vsp_read_kics_summary(ci_run_dir: str):
    try:
        from pathlib import Path as _P
        fp = _P(ci_run_dir) / "kics" / "kics_summary.json"
        if not fp.exists():
            return None
        import json as _json
        obj = _json.loads(fp.read_text(encoding="utf-8", errors="ignore") or "{}")
        if not isinstance(obj, dict):
            return None
        return obj
    except Exception:
        return None
# === END VSP_STATUS_INJECT_KICS_SUMMARY_V1 ===
''' % TAG

# place helper near top-level (after imports)
if "_vsp_read_kics_summary" not in t:
    # after last import block
    m=re.search(r'(^import .+\n|^from .+ import .+\n)+', t, flags=re.M)
    if m:
        ins=m.end()
        t=t[:ins]+"\n"+inject+"\n"+t[ins:]
    else:
        t=inject+"\n"+t

# now patch the after_request injector that already injects kics_tail
# find a safe anchor: where it sets payload["kics_tail"] or similar
pat = r'(payload\[[\'"]kics_tail[\'"]\]\s*=\s*[^ \n].*\n)'
m=re.search(pat, t)
if not m:
    # fallback: find after_request handler return payload
    m=re.search(r'return\s+jsonify\(\s*payload\s*\)', t)
    if not m:
        print("[ERR] cannot find injection anchor for payload/kics_tail/jsonify(payload)")
        raise SystemExit(2)
    anchor=m.start()
    insert_pos=anchor
else:
    insert_pos=m.end()

addon = r'''
    # %s
    try:
        ci_dir = payload.get("ci_run_dir") or payload.get("ci_run_dir_abs") or ""
        ks = _vsp_read_kics_summary(ci_dir) if ci_dir else None
        if isinstance(ks, dict):
            payload["kics_verdict"] = ks.get("verdict", "")
            payload["kics_counts"]  = ks.get("counts", {}) if isinstance(ks.get("counts"), dict) else {}
            payload["kics_total"]   = int(ks.get("total", 0) or 0)
        else:
            payload.setdefault("kics_verdict", "")
            payload.setdefault("kics_counts", {})
            payload.setdefault("kics_total", 0)
    except Exception:
        payload.setdefault("kics_verdict", "")
        payload.setdefault("kics_counts", {})
        payload.setdefault("kics_total", 0)
    # === END VSP_STATUS_INJECT_KICS_SUMMARY_V1 ===
''' % TAG

t = t[:insert_pos] + addon + t[insert_pos:]
p.write_text(t, encoding="utf-8")
print("[OK] injected kics_summary into status payload")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart 8910 =="
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
