#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ops_latest_${TS}"
echo "[OK] backup => ${APP}.bak_ops_latest_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_OPS_LATEST_API_V1"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

# insert imports if needed
if "from pathlib import Path" not in s:
    s = s.replace("import os", "import os\nfrom pathlib import Path")

# find a safe insertion point: after other /api routes
# We'll append near the end before `if __name__ == "__main__":` if present
ins = r'''
# --- {marker} ---
@app.get("/api/vsp/ops_latest_v1")
def api_vsp_ops_latest_v1():
    """
    Return latest OPS_STAMP.json and OPS PROOF.txt (best-effort).
    Artifacts live under out_ci/ops_stamp/<TS>/ and out_ci/ops_proof/<TS>/.
    """
    def latest_file(base: Path, rel: str):
        try:
            if not base.exists(): return None
            # pick latest TS dir
            dirs = [d for d in base.iterdir() if d.is_dir()]
            if not dirs: return None
            d = sorted(dirs, key=lambda x: x.stat().st_mtime, reverse=True)[0]
            f = d / rel
            if f.exists():
                return {"ts": d.name, "path": str(f), "text": f.read_text(encoding="utf-8", errors="replace")[:20000]}
            return {"ts": d.name, "path": str(f), "text": None}
        except Exception as e:
            return {"err": str(e)}

    root = Path(__file__).resolve().parent
    stamp = latest_file(root / "out_ci" / "ops_stamp", "OPS_STAMP.json")
    proof = latest_file(root / "out_ci" / "ops_proof", "PROOF.txt")
    return jsonify({"ver":"p1_ops_latest_v1", "stamp": stamp, "proof": proof})
# --- /{marker} ---
'''.format(marker=marker)

m = re.search(r'if __name__\s*==\s*["\']__main__["\']\s*:', s)
if m:
    s = s[:m.start()] + ins + "\n\n" + s[m.start():]
else:
    s += "\n\n" + ins

p.write_text(s, encoding="utf-8")
print("[OK] patched", marker)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile"
