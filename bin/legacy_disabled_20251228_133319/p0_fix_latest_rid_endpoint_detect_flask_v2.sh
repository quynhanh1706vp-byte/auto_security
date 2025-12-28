#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BASE="http://127.0.0.1:8910"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_fix_latest_rid_v2_${TS}"
echo "[BACKUP] ${WSGI}.bak_fix_latest_rid_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

start = "# ===================== VSP_P0_LATEST_RID_ENDPOINT_V1 ====================="
end   = "# ===================== /VSP_P0_LATEST_RID_ENDPOINT_V1 ====================="

if start not in s or end not in s:
    print("[ERR] marker block not found; cannot patch safely")
    sys.exit(2)

block = textwrap.dedent(r'''
# ===================== VSP_P0_LATEST_RID_ENDPOINT_V1 =====================
try:
    import time
    from pathlib import Path
    from flask import jsonify, Flask as _VSP_Flask

    # Find the real Flask() instance (application may be a middleware wrapper)
    _vsp_flask_app = None
    for _k, _v in list(globals().items()):
        try:
            if isinstance(_v, _VSP_Flask):
                _vsp_flask_app = _v
                break
        except Exception:
            pass

    def _vsp_latest_rid__impl_p0_v1():
        roots = [
            Path("/home/test/Data/SECURITY_BUNDLE/out"),
            Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
            Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
            Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        ]
        roots = [r for r in roots if r.exists() and r.is_dir()]
        must_files = ["run_gate_summary.json", "run_gate.json", "findings_unified.json"]

        cands = []
        for root in roots:
            try:
                for d in root.iterdir():
                    if not d.is_dir():
                        continue
                    rid = d.name
                    score = 0
                    if rid.startswith("VSP_"): score += 3
                    if rid.startswith("RUN_"): score += 2

                    have = []
                    for f in must_files:
                        fp = d / f
                        try:
                            if fp.exists() and fp.is_file() and fp.stat().st_size > 20:
                                have.append(f)
                        except Exception:
                            pass
                    if not have:
                        continue

                    try:
                        mtime = d.stat().st_mtime
                    except Exception:
                        continue

                    cands.append((mtime, score, rid, str(d), have))
            except Exception:
                continue

        if not cands:
            return jsonify({"ok": False, "err": "no run dir with gate artifacts found"}), 404

        cands.sort(key=lambda x: (x[0], x[1]), reverse=True)
        mtime, score, rid, path, have = cands[0]
        return jsonify({
            "ok": True,
            "rid": rid,
            "path": path,
            "have": have,
            "mtime": mtime,
            "mtime_iso": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mtime)),
            "roots_checked": [str(r) for r in roots],
        })

    if _vsp_flask_app is not None:
        # Idempotent register
        try:
            vf = getattr(_vsp_flask_app, "view_functions", {}) or {}
            if "vsp_latest_rid__p0_v1" not in vf:
                _vsp_flask_app.add_url_rule(
                    "/api/vsp/latest_rid",
                    endpoint="vsp_latest_rid__p0_v1",
                    view_func=_vsp_latest_rid__impl_p0_v1,
                    methods=["GET"],
                )
        except Exception:
            # fallback decorator-style
            _vsp_flask_app.route("/api/vsp/latest_rid", methods=["GET"])(_vsp_latest_rid__impl_p0_v1)
except Exception:
    pass
# ===================== /VSP_P0_LATEST_RID_ENDPOINT_V1 =====================
''').rstrip() + "\n"

pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
s2, n = pattern.subn(block.strip("\n"), s, count=1)
if n != 1:
    print("[ERR] failed to replace marker block safely")
    sys.exit(2)

p.write_text(s2, encoding="utf-8")
print("[OK] replaced latest_rid endpoint block with Flask-detection v2")
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" || true
systemctl --no-pager --full status "$SVC" | sed -n '1,18p' || true

echo "== verify latest_rid =="
curl -fsS "$BASE/api/vsp/latest_rid" | head -c 600; echo
