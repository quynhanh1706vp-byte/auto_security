#!/usr/bin/env bash
set -euo pipefail
APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_preempt_postprocess_statusv2_${TS}"
echo "[BACKUP] $APP.bak_preempt_postprocess_statusv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG_HELPER = "# === VSP_PREEMPT_STATUSV2_POSTPROCESS_HELPER_V1 ==="
TAG_HOOK   = "# === VSP_PREEMPT_STATUSV2_POSTPROCESS_HOOK_V1 ==="

if TAG_HELPER not in t:
    # Insert helper near other helpers (best effort: before first "if __name__" or append end)
    ins_pos = t.find("\nif __name__")
    if ins_pos == -1:
        ins_pos = len(t)

    helper = r'''
def _vsp_preempt_statusv2_postprocess_v1(payload):
    """Postprocess run_status_v2 JSON payload inside WSGI preempt to avoid nulls and inject tool summaries."""
    # === VSP_PREEMPT_STATUSV2_POSTPROCESS_HELPER_V1 ===
    try:
        import json
        from pathlib import Path as _P

        if not isinstance(payload, dict):
            return payload

        # never return nulls for commercial contract keys
        if payload.get("overall_verdict", None) is None:
            payload["overall_verdict"] = ""

        payload.setdefault("has_gitleaks", False)
        payload.setdefault("gitleaks_verdict", "")
        payload.setdefault("gitleaks_total", 0)
        payload.setdefault("gitleaks_counts", {})

        ci = payload.get("ci_run_dir") or payload.get("ci_dir") or payload.get("ci") or ""
        ci = str(ci).strip()
        if not ci:
            return payload

        # local helper read json
        def _readj(fp):
            try:
                if fp and fp.exists():
                    return json.loads(fp.read_text(encoding="utf-8", errors="ignore") or "{}")
            except Exception:
                return None
            return None

        # inject gitleaks from CI
        gsum = _readj(_P(ci) / "gitleaks" / "gitleaks_summary.json") or _readj(_P(ci) / "gitleaks_summary.json")
        if isinstance(gsum, dict):
            payload["has_gitleaks"] = True
            payload["gitleaks_verdict"] = str(gsum.get("verdict") or "")
            try:
                payload["gitleaks_total"] = int(gsum.get("total") or 0)
            except Exception:
                payload["gitleaks_total"] = 0
            cc = gsum.get("counts")
            payload["gitleaks_counts"] = cc if isinstance(cc, dict) else {}

        # if run_gate exists, take overall from it (single source of truth)
        gate = _readj(_P(ci) / "run_gate_summary.json")
        if isinstance(gate, dict):
            payload["overall_verdict"] = str(gate.get("overall") or payload.get("overall_verdict") or "")

        return payload
    except Exception:
        return payload
'''.strip("\n") + "\n\n"

    t = t[:ins_pos] + "\n\n" + helper + t[ins_pos:]
    print("[OK] inserted helper _vsp_preempt_statusv2_postprocess_v1")
else:
    print("[OK] helper exists, skip insert")

# Now hook: find ANY place in preempt that json.loads response body for run_status_v2
# We patch by inserting: payload = _vsp_preempt_statusv2_postprocess_v1(payload)
if TAG_HOOK in t:
    print("[OK] hook tag exists, skip")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

# Heuristic: find "run_status_v2" occurrences, then within next 1200 chars find "json.loads"
idxs = [m.start() for m in re.finditer(r"run_status_v2", t)]
if not idxs:
    raise SystemExit("[ERR] cannot find 'run_status_v2' anywhere in vsp_demo_app.py")

patched = False
for idx in idxs:
    window = t[idx: idx+6000]
    m = re.search(r"(?m)^(?P<ind>\s*)(?P<var>[A-Za-z_]\w*)\s*=\s*json\.loads\(", window)
    if not m:
        continue
    ind = m.group("ind")
    var = m.group("var")
    # insert after that line
    # find absolute position of end-of-line
    abs_line_start = idx + m.start()
    abs_eol = t.find("\n", abs_line_start)
    if abs_eol == -1:
        continue
    hook = "\n".join([
        f"{ind}{TAG_HOOK}",
        f"{ind}try:",
        f"{ind}    {var} = _vsp_preempt_statusv2_postprocess_v1({var})",
        f"{ind}except Exception:",
        f"{ind}    pass",
        ""
    ])
    t = t[:abs_eol+1] + hook + t[abs_eol+1:]
    patched = True
    print("[OK] inserted hook after json.loads into var=", var)
    break

if not patched:
    # fallback: patch any json.loads in file (rare but safe): first one
    m = re.search(r"(?m)^(?P<ind>\s*)(?P<var>[A-Za-z_]\w*)\s*=\s*json\.loads\(", t)
    if not m:
        raise SystemExit("[ERR] cannot find any assignment like X = json.loads(...)")
    ind = m.group("ind"); var = m.group("var")
    eol = t.find("\n", m.start())
    hook = "\n".join([
        f"{ind}{TAG_HOOK}",
        f"{ind}try:",
        f"{ind}    {var} = _vsp_preempt_statusv2_postprocess_v1({var})",
        f"{ind}except Exception:",
        f"{ind}    pass",
        ""
    ])
    t = t[:eol+1] + hook + t[eol+1:]
    print("[WARN] fallback hook inserted after first json.loads var=", var)

p.write_text(t, encoding="utf-8")
print("[OK] wrote patched vsp_demo_app.py")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile vsp_demo_app.py OK"
echo "DONE"
