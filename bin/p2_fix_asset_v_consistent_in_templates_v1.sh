#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
TEMPL_DIR="templates"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need find; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "== patch asset_v consistent (templates) ts=$TS =="

# 1) ensure wsgi injects asset_v from ENV (safe append-only)
python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_INJECT_ASSET_V_CTX_V1"

if marker in s:
    print("[OK] wsgi already has asset_v ctx marker")
    sys.exit(0)

# If app variable is named differently, this still usually works because most files use "app".
block = r'''
# --- VSP_P2_INJECT_ASSET_V_CTX_V1 ---
try:
    import os as _os
    @app.context_processor
    def _vsp_inject_asset_v_ctx():
        return {"asset_v": _os.environ.get("VSP_ASSET_V")}
except Exception:
    pass
# --- end VSP_P2_INJECT_ASSET_V_CTX_V1 ---
'''.lstrip("\n")

Path("wsgi_vsp_ui_gateway.py").write_text(s + "\n" + block + "\n", encoding="utf-8")
print("[OK] appended asset_v context_processor to wsgi")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK: $W"

# 2) patch templates: normalize any ?v={{ ... }} (except asset_v) into ?v={{ asset_v }}
if [ -d "$TEMPL_DIR" ]; then
  python3 - <<'PY'
from pathlib import Path
import re, time

root=Path("templates")
marker="VSP_P2_TEMPLATE_ASSET_V_CONSISTENT_V1"
changed_files=[]

# Replace patterns like ?v={{ something }} where "something" isn't "asset_v"
pat = re.compile(r'\?v=\{\{\s*([^}]+?)\s*\}\}')

for fp in sorted(root.rglob("*.html")):
    s=fp.read_text(encoding="utf-8", errors="replace")
    orig=s
    if marker not in s:
        # normalize all "?v={{...}}" to asset_v, but keep if already asset_v
        def repl(m):
            expr=m.group(1).strip()
            if expr == "asset_v":
                return m.group(0)
            # if expr looks like a constant number, still normalize
            return "?v={{ asset_v }}"
        s = pat.sub(repl, s)
        if s != orig:
            s += f"\n<!-- {marker} -->\n"
            bak = fp.with_suffix(fp.suffix + f".bak_assetv_{int(time.time())}")
            bak.write_text(orig, encoding="utf-8")
            fp.write_text(s, encoding="utf-8")
            changed_files.append(str(fp))
    else:
        # already patched once; still ensure any remaining non-asset_v patterns are fixed
        def repl2(m):
            expr=m.group(1).strip()
            return m.group(0) if expr == "asset_v" else "?v={{ asset_v }}"
        s2 = pat.sub(repl2, s)
        if s2 != s:
            bak = fp.with_suffix(fp.suffix + f".bak_assetv_{int(time.time())}")
            bak.write_text(s, encoding="utf-8")
            fp.write_text(s2, encoding="utf-8")
            changed_files.append(str(fp))

print("[OK] templates changed:", len(changed_files))
for f in changed_files[:200]:
    print(" -", f)
PY
else
  echo "[WARN] templates/ not found; skip template patch"
fi

# 3) restart service
if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting: $SVC"
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
else
  echo "[WARN] systemctl not found; restart manually"
fi

# 4) quick verify: same v= across tabs for the duplicated basenames
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== quick verify duplicated basenames now share same v= =="
for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "-- $pth --"
  curl -sS "$BASE$pth" | grep -oE '(vsp_(bundle_tabs5|dashboard_luxe|tabs4_autorid|topbar_commercial)_v1\.js\?v=[0-9]+)' | sort -u || true
done

echo "[OK] done"
