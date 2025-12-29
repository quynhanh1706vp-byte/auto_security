#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ops_latest_v3_${TS}"
echo "[OK] backup => ${APP}.bak_ops_latest_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

start = "# --- VSP_P1_OPS_LATEST_API_V2 ---"
end   = "# --- /VSP_P1_OPS_LATEST_API_V2 ---"

if start not in s or end not in s:
    raise SystemExit("[ERR] cannot find V2 ops_latest block markers")

pre, rest = s.split(start, 1)
mid, post = rest.split(end, 1)

block = r'''
# --- VSP_P1_OPS_LATEST_API_V3 ---
@app.get("/api/vsp/ops_latest_v1")
def api_vsp_ops_latest_v1():
    """
    Return latest OPS evidence by marker file (robust against extra folders/files).
    - stamp: out_ci/ops_stamp/<TS>/OPS_STAMP.json
    - proof: out_ci/ops_proof/<TS>/PROOF.txt
    - healthcheck: out_ci/ops_healthcheck/<TS>/healthcheck.log (optional)
    """
    from pathlib import Path as _Path
    import re as _re

    def _pick_latest_by_marker(base: _Path, marker: str):
        try:
            if not base.exists():
                return None
            # find marker under base/<ts>/<marker>
            hits = []
            for d in base.iterdir():
                if not d.is_dir():
                    continue
                f = d / marker
                if f.exists():
                    hits.append((f.stat().st_mtime, d, f))
            if not hits:
                return None
            hits.sort(key=lambda x: x[0], reverse=True)
            return hits[0][1], hits[0][2]
        except Exception:
            return None

    def _read_latest(base: _Path, marker: str, max_chars: int = 20000):
        picked = _pick_latest_by_marker(base, marker)
        if not picked:
            return None
        d, f = picked
        try:
            return {
                "ts": d.name,
                "path": str(f),
                "ok": True,
                "text": f.read_text(encoding="utf-8", errors="replace")[:max_chars],
            }
        except Exception as e:
            return {"ts": d.name, "path": str(f), "ok": False, "err": str(e), "text": None}

    root = _Path(__file__).resolve().parent
    stamp = _read_latest(root / "out_ci" / "ops_stamp", "OPS_STAMP.json")
    proof = _read_latest(root / "out_ci" / "ops_proof", "PROOF.txt")
    health = _read_latest(root / "out_ci" / "ops_healthcheck", "healthcheck.log", max_chars=12000)

    return jsonify({"ok": True, "ver": "p1_ops_latest_v1_v3", "stamp": stamp, "proof": proof, "healthcheck": health})
# --- /VSP_P1_OPS_LATEST_API_V3 ---
'''.lstrip("\n")

s2 = pre + block + post
p.write_text(s2, encoding="utf-8")
print("[OK] replaced ops_latest block with V3 (marker-based)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile"
