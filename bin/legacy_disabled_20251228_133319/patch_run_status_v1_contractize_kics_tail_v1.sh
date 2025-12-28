#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

# Tìm vsp_demo_app.py (không assume path cố định)
F="$(find . -maxdepth 4 -name 'vsp_demo_app.py' -type f | head -n 1 || true)"
[ -n "${F:-}" ] || { echo "[ERR] cannot find vsp_demo_app.py under $ROOT"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_contractize_kics_tail_${TS}"
echo "[BACKUP] $F.bak_contractize_kics_tail_${TS}"

python3 - <<'PY'
import re, json
from pathlib import Path

p = Path("""'"$F"'""")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG_HELP = "VSP_KICS_TAIL_HELPERS_V1"
TAG_INJ  = "VSP_RUN_STATUS_V1_KICS_TAIL_INJECT_V1"
TAG_CON  = "VSP_CONTRACTIZE_ALLOW_KICS_TAIL_V1"

changed = False

# 0) safe replace canonical-ish path typo (không phá cấu trúc)
repls = {
  "ui/ui/out_ci/uireq_v1": "ui/out_ci/uireq_v1",
  "/ui/ui/out_ci/uireq_v1": "/ui/out_ci/uireq_v1",
}
for a,b in repls.items():
  if a in txt:
    txt = txt.replace(a,b)
    changed = True

# 1) Ensure helper funcs exist (module-scope)
if TAG_HELP not in txt:
  # chèn sau import block đầu tiên (best-effort)
  m = re.search(r"(?ms)\A(.*?\n)(\s*(?:from|import)\s+[^\n]+\n(?:\s*(?:from|import)\s+[^\n]+\n)*)", txt)
  insert_at = m.end(0) if m else 0

  helper = f"""
# === {TAG_HELP} ===
def _vsp_safe_tail_text(_p, max_bytes=8192, max_lines=120):
    try:
        _p = Path(_p)
        if not _p.exists():
            return ""
        b = _p.read_bytes()
    except Exception:
        return ""
    if max_bytes and len(b) > max_bytes:
        b = b[-max_bytes:]
    try:
        s = b.decode("utf-8", errors="replace")
    except Exception:
        s = str(b)
    lines = s.splitlines()
    if max_lines and len(lines) > max_lines:
        lines = lines[-max_lines:]
    return "\\n".join(lines).strip()

def _vsp_kics_tail_from_ci(ci_run_dir):
    if not ci_run_dir:
        return ""
    try:
        base = Path(str(ci_run_dir))
    except Exception:
        return ""
    klog = base / "kics" / "kics.log"
    if klog.exists():
        t = _vsp_safe_tail_text(klog)
        return t if isinstance(t, str) else str(t)

    # degrade/missing tool hint
    djson = base / "degraded_tools.json"
    if djson.exists():
        try:
            raw = djson.read_text(encoding="utf-8", errors="ignore").strip() or "[]"
            data = json.loads(raw)
            items = data.get("degraded_tools", []) if isinstance(data, dict) else data
            for it in (items or []):
                tool = str((it or {}).get("tool","")).upper()
                if tool == "KICS":
                    rc = (it or {}).get("rc")
                    reason = (it or {}).get("reason") or (it or {}).get("msg") or "degraded"
                    return f"MISSING_TOOL: KICS (rc={rc}) reason={reason}"
        except Exception:
            pass

    # kics dir exists but no log
    if (base / "kics").exists():
        return f"NO_KICS_LOG: {klog}"
    return ""
# === END {TAG_HELP} ===
"""
  txt = txt[:insert_at] + helper + txt[insert_at:]
  changed = True

# 2) Best-effort: add kics_tail/_handler to contractize whitelist (nếu có literal list/set)
def patch_contractize_whitelist(t):
    m = re.search(r"(?m)^def\s+_vsp_contractize\s*\(.*?\)\s*:\s*$", t)
    if not m:
        return t, False, "no _vsp_contractize()"
    start = m.start()
    # end: next top-level def or decorator
    m2 = re.search(r"(?m)^(def\s+\w+\s*\(|@app\.route|@bp\.route)", t[m.end():])
    end = (m.end() + m2.start()) if m2 else len(t)
    block = t[start:end]

    if TAG_CON in block:
        return t, False, "already tagged"

    # common patterns: allowed_keys = {...} / [...] / set([...]) / tuple(...)
    pats = [
        r"(allowed_keys\s*=\s*\[)([^\]]*)(\])",
        r"(allowed_keys\s*=\s*\{)([^\}]*)(\})",
        r"(CONTRACT_KEYS\s*=\s*\[)([^\]]*)(\])",
        r"(CONTRACT_KEYS\s*=\s*\{)([^\}]*)(\})",
        r"(whitelist\s*=\s*\[)([^\]]*)(\])",
        r"(whitelist\s*=\s*\{)([^\}]*)(\})",
        r"(allowed\s*=\s*\[)([^\]]*)(\])",
        r"(allowed\s*=\s*\{)([^\}]*)(\})",
        r"(allowed_keys\s*=\s*set\(\s*\[)([^\]]*)(\]\s*\))",
    ]

    def ensure_keys(inner):
        # inner is the content inside [] or {}
        need = ["kics_tail", "_handler"]
        for k in need:
            if re.search(rf"['\"]{re.escape(k)}['\"]", inner):
                continue
            # append with comma (preserve style)
            inner = inner.rstrip()
            if inner and not inner.endswith((",", "\n")):
                inner += ", "
            inner += f"'{k}', "
        return inner

    for pat in pats:
        mm = re.search(pat, block, flags=re.S)
        if mm:
            pre, inner, suf = mm.group(1), mm.group(2), mm.group(3)
            inner2 = ensure_keys(inner)
            if inner2 != inner:
                block2 = block[:mm.start()] + pre + inner2 + suf + block[mm.end():]
                tag = f"\n    # === {TAG_CON} ===\n"
                # add tag near top of function (after def line)
                lines = block2.splitlines(True)
                for i,ln in enumerate(lines):
                    if ln.lstrip().startswith("def _vsp_contractize"):
                        # insert tag after def line
                        lines.insert(i+1, tag)
                        break
                block2 = "".join(lines)
                t2 = t[:start] + block2 + t[end:]
                return t2, True, "patched whitelist literal"
    return t, False, "no literal whitelist pattern matched"

txt2, ok2, msg2 = patch_contractize_whitelist(txt)
if ok2:
    txt = txt2
    changed = True

# 3) Inject kics_tail AFTER contractize inside run_status_v1 handler
def patch_run_status_handler(t):
    # find a route or function containing "run_status_v1"
    hit = re.search(r"(?m)^[^\n]*run_status_v1[^\n]*$", t)
    if not hit:
        return t, False, "no run_status_v1 token found"

    # try to locate function def following the decorator/area
    # find nearest "def ..." above or below where route mentions run_status_v1
    # approach: locate the def line AFTER the first route decorator that contains run_status_v1
    mroute = re.search(r"(?ms)^@.*run_status_v1[^\n]*\n\s*def\s+\w+\s*\(.*?\)\s*:\s*\n", t)
    if not mroute:
        # fallback: find def line containing run_status_v1 in name
        mroute = re.search(r"(?m)^def\s+\w*run_status_v1\w*\s*\(.*?\)\s*:\s*$", t)
        if not mroute:
            return t, False, "cannot locate handler def block"

    start = mroute.start()
    # end: next top-level def/decorator
    m2 = re.search(r"(?m)^(def\s+\w+\s*\(|@app\.route|@bp\.route)", t[mroute.end():])
    end = (mroute.end() + m2.start()) if m2 else len(t)

    block = t[start:end]
    if TAG_INJ in block:
        return t, False, "already injected"

    inj = f"""
    # === {TAG_INJ} ===
    try:
        _ci = (out.get("ci_run_dir") or out.get("ci_dir") or out.get("ci_run") or "")
        _kt = _vsp_kics_tail_from_ci(_ci) if _ci else ""
        out["kics_tail"] = _kt if isinstance(_kt, str) else str(_kt)
        out.setdefault("kics_tail", "")
        out["_handler"] = "vsp_demo_app.py:/api/vsp/run_status_v1"
    except Exception as _e:
        out["kics_tail"] = out.get("kics_tail","") or f"ERR_kics_tail:{_e}"
        out["_handler"] = out.get("_handler","") or "vsp_demo_app.py:/api/vsp/run_status_v1"
    # === END {TAG_INJ} ===
"""

    # insert after "out = _vsp_contractize(out)" (preferred)
    mcon = re.search(r"(?m)^\s*out\s*=\s*_vsp_contractize\s*\(\s*out\s*\)\s*$", block)
    if mcon:
        pos = mcon.end()
        block2 = block[:pos] + inj + block[pos:]
        return t[:start] + block2 + t[end:], True, "injected after contractize"

    # else insert before first "return jsonify"
    mret = re.search(r"(?m)^\s*return\s+jsonify\s*\(", block)
    if mret:
        pos = mret.start()
        block2 = block[:pos] + inj + block[pos:]
        return t[:start] + block2 + t[end:], True, "injected before return jsonify"

    # else: append at end of function block (still better than nothing)
    block2 = block + inj
    return t[:start] + block2 + t[end:], True, "injected at end (fallback)"

txt3, ok3, msg3 = patch_run_status_handler(txt)
if ok3:
    txt = txt3
    changed = True

if not changed:
    print("[OK] no changes needed")
else:
    p.write_text(txt, encoding="utf-8")
    print("[OK] patched:", p)

print("[INFO] contractize:", msg2)
print("[INFO] handler:", msg3)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] patch applied"
