#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kics_tail_fallback_${TS}"
echo "[BACKUP] $F.bak_kics_tail_fallback_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# Replace the whole _vsp_kics_tail_from_ci function (first match)
pat = r"(?ms)^\s*def\s+_vsp_kics_tail_from_ci\s*\(\s*ci_run_dir\s*\)\s*:\s*\n.*?(?=^\s*def\s+|\Z)"
m = re.search(pat, t)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp_kics_tail_from_ci(ci_run_dir)")

new_fn = r'''
def _vsp_kics_tail_from_ci(ci_run_dir):
    """
    Commercial guarantee:
      - If KICS log exists => return tail
      - Else try degraded_tools.json for KICS (rc/reason)
      - Else try runner.log tail for KICS rc=127 / command not found / No such file / timeout
      - Else if CI dir hints KICS stage => return explicit NO_KICS_LOG/NO_EVIDENCE message (NOT empty)
      - Else return "" (non-KICS runs)
    """
    if not ci_run_dir:
        return ""
    try:
        base = _vsp_Path(str(ci_run_dir))
    except Exception:
        return ""

    # 1) kics.log
    klog = base / "kics" / "kics.log"
    if klog.exists():
        return _vsp_safe_tail_text(klog)

    # 2) degraded_tools.json (either list or {"degraded_tools":[...]})
    for dj in (base / "degraded_tools.json",):
        if dj.exists():
            try:
                raw = dj.read_text(encoding="utf-8", errors="ignore").strip() or "[]"
                data = _vsp_json.loads(raw)
                items = data.get("degraded_tools", []) if isinstance(data, dict) else data
                for it in (items or []):
                    tool = str((it or {}).get("tool","")).upper()
                    if tool == "KICS":
                        rc = (it or {}).get("rc")
                        reason = (it or {}).get("reason") or (it or {}).get("msg") or "degraded"
                        return "MISSING_TOOL: KICS (rc=%s) reason=%s" % (rc, reason)
            except Exception:
                pass

    # 3) runner.log fallback (best effort)
    rlog = base / "runner.log"
    if rlog.exists():
        tail = _vsp_safe_tail_text(rlog, max_bytes=16384, max_lines=200)
        up = tail.upper()
        # detect KICS-related failures
        if "KICS" in up:
            # common missing/rc patterns
            if ("RC=127" in up) or ("COMMAND NOT FOUND" in up) or ("NO SUCH FILE" in up) or ("NOT FOUND" in up):
                # include last few lines containing KICS / rc=127 / not found
                lines = tail.splitlines()
                keep = []
                for ln in lines[-200:]:
                    u = ln.upper()
                    if ("KICS" in u) or ("RC=127" in u) or ("COMMAND NOT FOUND" in u) or ("NO SUCH FILE" in u) or ("NOT FOUND" in u):
                        keep.append(ln)
                msg = "\n".join(keep[-30:]).strip() or tail
                return "MISSING_TOOL: KICS (from runner.log)\n" + msg

            if ("TIMEOUT" in up) or ("RC=124" in up):
                return "TIMEOUT: KICS (from runner.log)\n" + tail

            # KICS mentioned but no explicit error: still give useful context
            return "NO_KICS_LOG: %s\n(from runner.log)\n%s" % (klog, tail)

    # 4) heuristic: CI dir hints KICS stage (kics folder exists or stage marker exists somewhere)
    if (base / "kics").exists():
        return "NO_KICS_LOG: %s" % (klog,)

    # runner.log missing, kics dir missing: cannot assert it's KICS stage
    return ""
'''.lstrip("\n")

t2 = t[:m.start()] + new_fn + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] replaced _vsp_kics_tail_from_ci()")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] patch applied"
