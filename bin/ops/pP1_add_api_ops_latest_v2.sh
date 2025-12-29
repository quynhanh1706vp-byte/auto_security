#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ops_latest_v2_${TS}"
echo "[OK] backup => ${APP}.bak_ops_latest_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_OPS_LATEST_API_V2"
route_path = "/api/vsp/ops_latest_v1"

if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

# ---- (A) allowlist: insert ops_latest next to healthz if possible ----
if route_path not in s:
    lines = s.splitlines(True)
    inserted = False
    for i, line in enumerate(lines):
        if "/api/vsp/healthz" in line:
            # heuristic: looks like allowlist section if nearby mentions allow/allowed/whitelist
            window = "".join(lines[max(0, i-6):i+1]).lower()
            if ("allow" in window) or ("whitelist" in window) or ("allowed" in window):
                indent = re.match(r"^(\s*)", line).group(1)
                quote = "'" if "'" in line else '"'
                # keep comma style
                comma = "," if line.rstrip().endswith((",", "],", "},", "]", "}",)) or "," in line else ","
                new_line = f"{indent}{quote}{route_path}{quote}{comma}\n"
                lines.insert(i+1, new_line)
                inserted = True
                break
    if inserted:
        s = "".join(lines)
        print("[OK] allowlist: inserted ops_latest near healthz")
    else:
        print("[WARN] allowlist: could not locate obvious list; route may still be blocked until you add it manually")

# ---- (B) insert route (no .format, no brace issues) ----
ins = (
    "\n# --- " + marker + " ---\n"
    "@app.get(\"" + route_path + "\")\n"
    "def api_vsp_ops_latest_v1():\n"
    "    \"\"\"Return latest OPS_STAMP.json and PROOF.txt (best-effort).\"\"\"\n"
    "    from pathlib import Path as _Path\n"
    "    def _latest_ts_dir(base: _Path):\n"
    "        try:\n"
    "            if not base.exists():\n"
    "                return None\n"
    "            dirs = [d for d in base.iterdir() if d.is_dir()]\n"
    "            if not dirs:\n"
    "                return None\n"
    "            return sorted(dirs, key=lambda x: x.stat().st_mtime, reverse=True)[0]\n"
    "        except Exception:\n"
    "            return None\n"
    "\n"
    "    def _read_latest(base: _Path, rel: str):\n"
    "        try:\n"
    "            d = _latest_ts_dir(base)\n"
    "            if not d:\n"
    "                return None\n"
    "            f = d / rel\n"
    "            return {\n"
    "                \"ts\": d.name,\n"
    "                \"path\": str(f),\n"
    "                \"ok\": f.exists(),\n"
    "                \"text\": (f.read_text(encoding=\"utf-8\", errors=\"replace\")[:20000] if f.exists() else None),\n"
    "            }\n"
    "        except Exception as e:\n"
    "            return {\"err\": str(e)}\n"
    "\n"
    "    root = _Path(__file__).resolve().parent\n"
    "    stamp = _read_latest(root / \"out_ci\" / \"ops_stamp\", \"OPS_STAMP.json\")\n"
    "    proof = _read_latest(root / \"out_ci\" / \"ops_proof\", \"PROOF.txt\")\n"
    "    return jsonify({\"ok\": True, \"ver\": \"p1_ops_latest_v1\", \"stamp\": stamp, \"proof\": proof})\n"
    "# --- /" + marker + " ---\n"
)

m = re.search(r'if __name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s = s[:m.start()] + ins + "\n\n" + s[m.start():]
else:
    s += "\n\n" + ins

p.write_text(s, encoding="utf-8")
print("[OK] route inserted:", route_path)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile"
