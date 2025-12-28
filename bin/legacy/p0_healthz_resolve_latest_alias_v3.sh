#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_healthz_latestfix_${TS}"
echo "[BACKUP] ${APP}.bak_healthz_latestfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P0_HEALTHZ_V1" not in s:
    raise SystemExit("[ERR] healthz marker not found")

# Patch: right before "return best or """ in _health_rid_latest_gate_root, add resolve logic
pat = r"(def _health_rid_latest_gate_root\(\):.*?)(\n\s*return best or \"\"\s*\n)"
m = re.search(pat, s, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot locate rid_latest_gate_root return")

prefix = m.group(1)
ret = m.group(2)

if "VSP_P0_HEALTHZ_LATEST_ALIAS_RESOLVE_V3" in s:
    print("[OK] already patched")
    raise SystemExit(0)

inject = r'''

    # --- VSP_P0_HEALTHZ_LATEST_ALIAS_RESOLVE_V3 ---
    # If best is a generic alias like "latest", try to resolve to actual RID for nicer UX.
    try:
        if best == "latest":
            for root in roots:
                lp = root / "latest"
                if lp.exists():
                    # 1) if symlink, resolve target name
                    try:
                        if lp.is_symlink():
                            tgt = lp.resolve()
                            if tgt and tgt.name and tgt.name != "latest":
                                best = tgt.name
                                break
                    except Exception:
                        pass

                    # 2) if latest is a dir, try read run id from known files
                    try:
                        if lp.is_dir():
                            for fn in ("RUN_ID", "run_id.txt", "rid.txt"):
                                f = lp / fn
                                if f.is_file() and f.stat().st_size > 0:
                                    rid = f.read_text(encoding="utf-8", errors="replace").strip()
                                    if rid and rid != "latest":
                                        best = rid
                                        break
                            if best != "latest":
                                break
                    except Exception:
                        pass

                    # 3) as last resort, try parse rid from run_gate_summary.json inside latest
                    try:
                        rg = lp / "run_gate_summary.json"
                        if rg.is_file() and rg.stat().st_size > 0:
                            import json
                            j = json.loads(rg.read_text(encoding="utf-8", errors="replace"))
                            rid = (j.get("rid") or j.get("run_id") or j.get("id") or "").strip()
                            if rid and rid != "latest":
                                best = rid
                                break
                    except Exception:
                        pass
    except Exception:
        pass
    # --- /VSP_P0_HEALTHZ_LATEST_ALIAS_RESOLVE_V3 ---
'''

# Insert inject before return
s2 = prefix + inject + ret + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted latest alias resolve v3")
PY

echo "== compile check =="
python3 -m py_compile "$APP"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] latest alias resolve v3 applied."
