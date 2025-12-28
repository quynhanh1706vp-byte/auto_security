#!/usr/bin/env bash
set -euo pipefail
APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_inject_tool_summary_generic_${TS}"
echo "[BACKUP] $APP.bak_inject_tool_summary_generic_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_INJECT_TOOL_SUMMARY_GENERIC_V1 ==="

# Replace existing def _vsp_inject_tool_summary(...) if present
m = re.search(r"(?m)^def\s+_vsp_inject_tool_summary\s*\(.*?\):\s*$", t)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp_inject_tool_summary(...) in vsp_demo_app.py")

start = m.start()
# function ends at next top-level def
m2 = re.search(r"(?m)^def\s+\w+\s*\(.*?\):\s*$", t[m.end():])
end = (m.end() + m2.start()) if m2 else len(t)

new_func = r'''
def _vsp_inject_tool_summary(resp, ci_dir, tool, summary_name):
    """
    Generic injector for tool summary into run_status_v2 payload.
    - Looks for:  <ci_dir>/<tool>/<summary_name>  OR <ci_dir>/<summary_name>
    - Injects:
        has_<tool> (bool)
        <tool>_verdict (str)
        <tool>_total (int)
        <tool>_counts (dict)
    """
    # === VSP_INJECT_TOOL_SUMMARY_GENERIC_V1 ===
    try:
        import os, json
        from pathlib import Path as _P
        if not isinstance(resp, dict):
            return resp
        ci = str(ci_dir or "")
        if not ci:
            return resp

        tool_key = str(tool or "").strip().lower()
        if not tool_key:
            return resp

        fp1 = _P(ci) / tool_key / str(summary_name)
        fp2 = _P(ci) / str(summary_name)
        fp = fp1 if fp1.exists() else fp2 if fp2.exists() else None
        if fp is None:
            # ensure contract keys exist even if missing
            resp.setdefault(f"has_{tool_key}", False)
            resp.setdefault(f"{tool_key}_verdict", "")
            resp.setdefault(f"{tool_key}_total", 0)
            resp.setdefault(f"{tool_key}_counts", {})
            return resp

        try:
            obj = json.loads(fp.read_text(encoding="utf-8", errors="ignore") or "{}")
        except Exception:
            obj = {}

        if isinstance(obj, dict):
            resp[f"has_{tool_key}"] = True
            resp[f"{tool_key}_verdict"] = str(obj.get("verdict") or "")
            try:
                resp[f"{tool_key}_total"] = int(obj.get("total") or 0)
            except Exception:
                resp[f"{tool_key}_total"] = 0
            cc = obj.get("counts")
            resp[f"{tool_key}_counts"] = cc if isinstance(cc, dict) else {}
        else:
            resp.setdefault(f"has_{tool_key}", False)
            resp.setdefault(f"{tool_key}_verdict", "")
            resp.setdefault(f"{tool_key}_total", 0)
            resp.setdefault(f"{tool_key}_counts", {})

        return resp
    except Exception:
        return resp
'''.strip("\n") + "\n\n"

t2 = t[:start] + new_func + t[end:]
p.write_text(t2, encoding="utf-8")
print("[OK] replaced _vsp_inject_tool_summary with generic version")

# Also ensure default keys for gitleaks exist somewhere in payload init (best-effort insert)
txt = p.read_text(encoding="utf-8", errors="ignore")
if "has_gitleaks" not in txt:
    # insert near existing kics/semgrep/trivy setdefault area
    mm = re.search(r"(?m)^\s*payload\.setdefault\(\"kics_verdict\"", txt)
    if mm:
        ind = re.match(r"(?m)^(?P<ind>\s*)payload\.setdefault", txt[mm.start():]).group("ind")
        ins = "\n".join([
            f"{ind}# === VSP_PAYLOAD_DEFAULT_GITLEAKS_V1 ===",
            f"{ind}payload.setdefault(\"has_gitleaks\", False)",
            f"{ind}payload.setdefault(\"gitleaks_verdict\", \"\")",
            f"{ind}payload.setdefault(\"gitleaks_total\", 0)",
            f"{ind}payload.setdefault(\"gitleaks_counts\", {{}})",
            ""
        ])
        pos = mm.start()
        txt = txt[:pos] + ins + txt[pos:]
        p.write_text(txt, encoding="utf-8")
        print("[OK] inserted gitleaks payload defaults near kics defaults")
    else:
        print("[WARN] could not find payload.setdefault(kics_verdict) anchor for defaults")
else:
    print("[OK] gitleaks keys already present somewhere (skip defaults insert)")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile vsp_demo_app.py OK"
echo "DONE"
