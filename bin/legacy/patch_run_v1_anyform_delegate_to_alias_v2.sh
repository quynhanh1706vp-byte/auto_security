#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_anyform_${TS}"
echo "[BACKUP] $F.bak_runv1_anyform_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_ANYFORM_DELEGATE_TO_ALIAS_V2 ==="
END = "# === END VSP_RUN_V1_ANYFORM_DELEGATE_TO_ALIAS_V2 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# --- helpers ---
def find_def_block(text: str, fn_name: str):
    m = re.search(rf"(?m)^def\s+{re.escape(fn_name)}\s*\(\s*\)\s*:\s*$", text)
    if not m:
        return None
    start = m.start()
    mnext = re.search(r"(?m)^def\s+\w+\s*\(", text[m.end():])
    end = (m.end() + mnext.start()) if mnext else len(text)
    return start, end

def detect_body_indent(seg: str) -> str:
    lines = seg.splitlines(True)
    for ln in lines[1:]:
        if ln.strip() == "":
            continue
        m = re.match(r"^([ \t]+)", ln)
        return m.group(1) if m else "    "
    return "    "

def inject_delegate(seg: str) -> str:
    if "return vsp_run_v1_alias()" in seg:
        return seg
    indent = detect_body_indent(seg)
    lines = seg.splitlines(True)

    # insert after docstring if any
    insert_at = 1
    if len(lines) > 1:
        m = re.match(rf"^{re.escape(indent)}(['\"]{{3}})", lines[1])
        if m:
            q = m.group(1)
            j = 2
            while j < len(lines):
                if q in lines[j]:
                    insert_at = j + 1
                    break
                j += 1

    block = (
        f"{indent}{TAG}\n"
        f"{indent}# Commercial: force /api/vsp/run_v1 to behave exactly like vsp_run_v1_alias (defaults + env_overrides)\n"
        f"{indent}return vsp_run_v1_alias()\n"
        f"{indent}{END}\n"
    )
    lines.insert(insert_at, block)
    return "".join(lines)

# --- locate handler(s) bound to /api/vsp/run_v1 ---
lines = t.splitlines(True)
hits = [i for i,ln in enumerate(lines) if "/api/vsp/run_v1" in ln]
if not hits:
    raise SystemExit("[ERR] cannot find '/api/vsp/run_v1' string anywhere in vsp_demo_app.py")

candidates = []

for i in hits:
    # case A: decorator block (@app.route / @app.post / @bp.route ...) possibly multi-line
    # walk up a few lines to find a decorator start '@'
    j = i
    while j >= 0 and (i - j) <= 12:
        if lines[j].lstrip().startswith("@"):
            # from j forward, find next def
            k = j
            while k < len(lines) and (k - j) <= 40:
                mdef = re.match(r"^\s*def\s+([A-Za-z_]\w*)\s*\(\s*\)\s*:\s*$", lines[k])
                if mdef:
                    candidates.append(mdef.group(1))
                    break
                k += 1
            break
        j -= 1

    # case B: add_url_rule(...) style
    ln = lines[i]
    if "add_url_rule" in ln:
        m = re.search(r"view_func\s*=\s*([A-Za-z_]\w*)", ln)
        if m:
            candidates.append(m.group(1))
        else:
            # try capture last positional function name before ')'
            m2 = re.search(r",\s*([A-Za-z_]\w*)\s*\)\s*$", ln.strip())
            if m2:
                candidates.append(m2.group(1))

# de-dup keep order
seen=set(); candidates=[c for c in candidates if not (c in seen or seen.add(c))]

if not candidates:
    # fallback: maybe a proxy function named api_vsp_run_v1 or vsp_run_v1 exists; try guess by searching near hits
    window = "".join(lines[max(0, hits[0]-80): min(len(lines), hits[0]+120)])
    mguess = re.search(r"(?m)^\s*def\s+([A-Za-z_]\w*run_v1[A-Za-z_]\w*)\s*\(", window)
    if mguess:
        candidates = [mguess.group(1)]

if not candidates:
    raise SystemExit("[ERR] found /api/vsp/run_v1 but could not infer handler function name")

patched = 0
for fn in candidates:
    blk = find_def_block(t, fn)
    if not blk:
        continue
    s,e = blk
    seg = t[s:e]
    seg2 = inject_delegate(seg)
    if seg2 != seg:
        t = t[:s] + seg2 + t[e:]
        patched += 1

if patched == 0:
    raise SystemExit(f"[ERR] handler candidates={candidates} but none patched (defs not found or already delegated)")

p.write_text(t, encoding="utf-8")
print(f"[OK] patched run_v1 handlers -> delegate to vsp_run_v1_alias(), patched_n={patched}, candidates={candidates}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify /api/vsp/run_v1 minimal payload =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d '{}' | sed -n '1,120p'
