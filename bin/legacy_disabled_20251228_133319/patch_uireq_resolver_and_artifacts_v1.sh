#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_uireq_resolve_art_${TS}"
echo "[BACKUP] $F.bak_uireq_resolve_art_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# ensure imports
if not re.search(r"(?m)^\s*import\s+os\s*$", t):
    t = "import os\n" + t
if not re.search(r"(?m)^\s*import\s+json\s*$", t):
    t = "import json\n" + t

HELP_TAG = "# === VSP_UIREQ_RESOLVE_HELPER_V1 ==="
HELP_END = "# === END VSP_UIREQ_RESOLVE_HELPER_V1 ==="
if HELP_TAG not in t:
    helper = f"""
{HELP_TAG}
def _vsp_resolve_uireq_to_ci_dir_v1(rid: str):
    # Try known state locations (commercial safe)
    candidates = [
        f"/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1/{{rid}}.json",
        f"/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_req_state/{{rid}}.json",
    ]
    for sp in candidates:
        try:
            if os.path.exists(sp):
                with open(sp, "r", encoding="utf-8") as f:
                    j = json.load(f) if f else None
                if isinstance(j, dict):
                    ci = j.get("ci_run_dir") or j.get("ci_dir") or j.get("run_dir")
                    if ci and isinstance(ci, str):
                        return ci
        except Exception:
            pass
    return None
{HELP_END}
"""
    t = t.rstrip() + "\n\n" + helper + "\n"

def patch_func(name: str, inject_code: str, tag: str):
    global t
    m = re.search(rf"(?m)^def\s+{re.escape(name)}\s*\(\s*rid\s*\)\s*:\s*$", t)
    if not m:
        return False, f"[WARN] cannot find def {name}(rid)"
    start = m.start()
    mnext = re.search(r"(?m)^def\s+\w+\s*\(", t[m.end():])
    end = (m.end() + mnext.start()) if mnext else len(t)
    seg = t[start:end]

    if tag in seg:
        return True, f"[OK] {name} already patched"

    # detect indent inside function
    lines = seg.splitlines(True)
    indent = None
    for ln in lines[1:]:
        if ln.strip()=="":
            continue
        mm = re.match(r"^([ \t]+)", ln)
        indent = mm.group(1) if mm else "    "
        break
    indent = indent or "    "

    # inject after possible docstring
    insert_at = 1
    if len(lines) > 1:
        mm = re.match(rf"^{re.escape(indent)}(['\"]{{3}})", lines[1])
        if mm:
            q = mm.group(1)
            j = 2
            while j < len(lines):
                if q in lines[j]:
                    insert_at = j + 1
                    break
                j += 1

    block = "\n" + "\n".join(indent + s for s in inject_code.strip("\n").splitlines()) + "\n"
    lines.insert(insert_at, block)
    seg2 = "".join(lines)
    t = t[:start] + seg2 + t[end:]
    return True, f"[OK] patched {name}"

ok1, msg1 = patch_func(
    "vsp_run_status_v1_fs_resolver",
    r'''
# === VSP_UIREQ_RESOLVER_PATCH_V1 ===
# Accept UI request ids and resolve to CI run dir/id
if isinstance(rid, str) and rid.startswith("VSP_UIREQ_"):
    ci = _vsp_resolve_uireq_to_ci_dir_v1(rid)
    if ci:
        rid_norm = os.path.basename(ci)
        return jsonify({"ok": True, "rid_norm": rid_norm, "ci_run_dir": ci, "source": "uireq_state"})
# === END VSP_UIREQ_RESOLVER_PATCH_V1 ===
''',
    "# === VSP_UIREQ_RESOLVER_PATCH_V1 ==="
)

ok2, msg2 = patch_func(
    "vsp_run_artifacts_index_v1",
    r'''
# === VSP_UIREQ_ARTIFACTS_ACCEPT_V1 ===
# If UIREQ provided, resolve to CI RID first
if isinstance(rid, str) and rid.startswith("VSP_UIREQ_"):
    ci = _vsp_resolve_uireq_to_ci_dir_v1(rid)
    if ci:
        rid = os.path.basename(ci)
# === END VSP_UIREQ_ARTIFACTS_ACCEPT_V1 ===
''',
    "# === VSP_UIREQ_ARTIFACTS_ACCEPT_V1 ==="
)

p.write_text(t, encoding="utf-8")
print(msg1)
print(msg2)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== quick check resolver with a known UIREQ =="
RID="$(ls -1 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1/*.json 2>/dev/null | tail -n 1 | xargs -r basename | sed 's/\.json$//' || true)"
if [ -n "${RID:-}" ]; then
  echo "RID=$RID"
  curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v1_fs_resolver/$RID" | jq '{ok,rid_norm,ci_run_dir,source}'
  echo "== artifacts index =="
  curl -sS -o /dev/null -w "HTTP=%{http_code}\n" "http://127.0.0.1:8910/api/vsp/run_artifacts_index_v1/$RID"
else
  echo "[SKIP] no UIREQ state json found under out_ci/uireq_v1/*.json"
fi
